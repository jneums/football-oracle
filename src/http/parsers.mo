// API response parsers for different football data providers
import HttpTypes "types";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import D "mo:base/Debug";
import Json "mo:json/lib";
import Result "mo:base/Result";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Float "mo:base/Float";

module {
  public type Score = HttpTypes.Score;
  public type MatchStatus = HttpTypes.MatchStatus;

  /// Parse match status from API-Football status code
  private func parseMatchStatus(statusShort : Text) : MatchStatus {
    switch (statusShort) {
      // Not Started
      case ("TBD") { #NotStarted };
      case ("NS") { #NotStarted };

      // In Progress
      case ("1H") { #InProgress };
      case ("HT") { #InProgress };
      case ("2H") { #InProgress };
      case ("ET") { #InProgress };
      case ("BT") { #InProgress }; // Break Time
      case ("P") { #InProgress }; // Penalty
      case ("SUSP") { #InProgress }; // Suspended
      case ("INT") { #InProgress }; // Interrupted
      case ("LIVE") { #InProgress };

      // Finished
      case ("FT") { #Finished };
      case ("AET") { #Finished }; // After Extra Time
      case ("PEN") { #Finished }; // Penalties

      // Cancelled/Postponed
      case ("PST") { #Postponed };
      case ("CANC") { #Cancelled };
      case ("ABD") { #Abandoned };
      case ("AWD") { #Finished }; // Technical Loss/Awarded
      case ("WO") { #Finished }; // WalkOver

      // Unknown
      case (_) {
        D.print("Unknown match status: " # statusShort);
        #Unknown;
      };
    };
  };

  /// Parse API-Football response using proper JSON parsing
  /// Expected format: { "response": [{ "fixture": {...}, "goals": { "home": 2, "away": 1 }, "fixture": { "status": { "short": "FT" } } }] }
  public func parseApiFootball(body : Blob, _matchId : Text) : ?Score {
    let text = switch (Text.decodeUtf8(body)) {
      case null {
        D.print("API-Football: Failed to decode UTF8");
        return null;
      };
      case (?t) { t };
    };

    D.print("API-Football: Parsing response with Json library");

    let parsed = Json.parse(text);
    switch (parsed) {
      case (#err(e)) {
        D.print("API-Football: JSON parse error: " # Json.errToText(e));
        return null;
      };
      case (#ok(json)) {
        // Extract status from response[0].fixture.status.short
        let statusShort = switch (Result.toOption(Json.getAsText(json, "response[0].fixture.status.short"))) {
          case null {
            D.print("API-Football: Failed to extract status from response[0].fixture.status.short");
            return null;
          };
          case (?s) { s };
        };

        let matchStatus = parseMatchStatus(statusShort);
        D.print("API-Football: Match status: " # statusShort # " -> " # debug_show (matchStatus));

        // Extract goals from response[0].goals.home and response[0].goals.away
        let homeScore = switch (Result.toOption(Json.getAsFloat(json, "response[0].goals.home"))) {
          case null {
            D.print("API-Football: Home goals is null, using 0");
            0;
          };
          case (?h) { Int.abs(Float.toInt(h)) };
        };

        let awayScore = switch (Result.toOption(Json.getAsFloat(json, "response[0].goals.away"))) {
          case null {
            D.print("API-Football: Away goals is null, using 0");
            0;
          };
          case (?a) { Int.abs(Float.toInt(a)) };
        };

        D.print("API-Football: Successfully parsed scores: " # debug_show (homeScore) # "-" # debug_show (awayScore));
        ?{ home = homeScore; away = awayScore; status = matchStatus };
      };
    };
  };

  /// Parse TheSportsDB response
  /// Expected format: { "events": [{ "intHomeScore": "2", "intAwayScore": "1" }] }
  public func parseTheSportsDB(body : Blob, _matchId : Text) : ?Score {
    let text = switch (Text.decodeUtf8(body)) {
      case null { return null };
      case (?t) { t };
    };

    // MEMORY FIX: Don't log full response (can be 100KB!)
    // D.print("TheSportsDB response: " # text);

    let parsed = Json.parse(text);
    switch (parsed) {
      case (#err(e)) {
        D.print("TheSportsDB: JSON parse error: " # Json.errToText(e));
        return null;
      };
      case (#ok(json)) {
        // Use path-based navigation: events[0].intHomeScore and events[0].intAwayScore
        let homeScore = switch (Result.toOption(Json.getAsText(json, "events[0].intHomeScore"))) {
          case null {
            D.print("TheSportsDB: Failed to get home score from path events[0].intHomeScore");
            return null;
          };
          case (?h) {
            switch (Nat.fromText(h)) {
              case null {
                D.print("TheSportsDB: Failed to convert home score text to Nat: " # h);
                return null;
              };
              case (?n) { n };
            };
          };
        };
        let awayScore = switch (Result.toOption(Json.getAsText(json, "events[0].intAwayScore"))) {
          case null {
            D.print("TheSportsDB: Failed to get away score from path events[0].intAwayScore");
            return null;
          };
          case (?a) {
            switch (Nat.fromText(a)) {
              case null {
                D.print("TheSportsDB: Failed to convert away score text to Nat: " # a);
                return null;
              };
              case (?n) { n };
            };
          };
        };
        D.print("TheSportsDB: Successfully parsed scores: " # debug_show (homeScore) # "-" # debug_show (awayScore));
        ?{ home = homeScore; away = awayScore; status = #Unknown };
      };
    };
  };

  /// Parse Football-Data.org response
  /// Expected format: { "match": { "score": { "fullTime": { "home": 2, "away": 1 } } } }
  public func parseFootballData(body : Blob, _matchId : Text) : ?Score {
    let text = switch (Text.decodeUtf8(body)) {
      case null { return null };
      case (?t) { t };
    };

    // MEMORY FIX: Don't log full response (can be 100KB!)
    // D.print("Football-Data response: " # text);

    let parsed = Json.parse(text);
    switch (parsed) {
      case (#err(e)) {
        D.print("Football-Data: JSON parse error: " # Json.errToText(e));
        return null;
      };
      case (#ok(json)) {
        // Use path-based navigation: match.score.fullTime.home and match.score.fullTime.away
        let homeScore = switch (Result.toOption(Json.getAsFloat(json, "match.score.fullTime.home"))) {
          case null {
            D.print("Football-Data: Failed to get home score from path match.score.fullTime.home");
            return null;
          };
          case (?h) { Int.abs(Float.toInt(h)) };
        };
        let awayScore = switch (Result.toOption(Json.getAsFloat(json, "match.score.fullTime.away"))) {
          case null {
            D.print("Football-Data: Failed to get away score from path match.score.fullTime.away");
            return null;
          };
          case (?a) { Int.abs(Float.toInt(a)) };
        };
        D.print("Football-Data: Successfully parsed scores: " # debug_show (homeScore) # "-" # debug_show (awayScore));
        ?{ home = homeScore; away = awayScore; status = #Unknown };
      };
    };
  };
};
