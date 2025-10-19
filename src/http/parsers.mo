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

  /// Lightweight JSON value extractor - avoids parsing entire JSON tree
  /// Finds a JSON field and extracts its value as text
  private func extractJsonValue(jsonText : Text, fieldName : Text) : ?Text {
    // Search for the field name in quotes
    let searchFor = "\"" # fieldName # "\"";

    let textChars = Text.toArray(jsonText);
    let searchChars = Text.toArray(searchFor);

    // Find the pattern
    var matchPos = 0;
    var foundAt : ?Nat = null;

    for (i in textChars.keys()) {
      if (textChars[i] == searchChars[matchPos]) {
        matchPos += 1;
        if (matchPos == searchChars.size()) {
          foundAt := ?(i + 1);
          matchPos := 0;
        };
      } else {
        matchPos := 0;
        // Restart matching if we see the first character
        if (textChars[i] == searchChars[0]) {
          matchPos := 1;
        };
      };
    };

    let ?startPos = foundAt else return null;
    var i = startPos;

    // Skip whitespace and find colon
    label colonLoop while (i < textChars.size()) {
      let c = textChars[i];
      if (c == ':') {
        i += 1;
        break colonLoop;
      };
      if (c != ' ' and c != '\n' and c != '\r' and c != '\t') {
        return null;
      };
      i += 1;
    };

    // Skip whitespace after colon
    label wsLoop while (i < textChars.size()) {
      let c = textChars[i];
      if (c == ' ' or c == '\n' or c == '\r' or c == '\t') {
        i += 1;
      } else {
        break wsLoop;
      };
    };

    if (i >= textChars.size()) {
      return null;
    };

    // Extract the value
    let firstChar = textChars[i];
    if (firstChar == '\"') {
      // String value
      i += 1;
      var value = "";
      label stringLoop while (i < textChars.size()) {
        let c = textChars[i];
        if (c == '\"') {
          return ?value;
        };
        // Handle escaped quotes (basic support)
        if (c == '\\' and i + 1 < textChars.size() and textChars[i + 1] == '\"') {
          value #= "\"";
          i += 2;
        } else {
          value #= Text.fromChar(c);
          i += 1;
        };
      };
      return null;
    } else if (firstChar == 'n') {
      // null value
      return ?"null";
    } else {
      // Number - extract until delimiter
      var value = "";
      while (i < textChars.size()) {
        let c = textChars[i];
        if (c == ',' or c == '}' or c == ']' or c == ' ' or c == '\n' or c == '\r' or c == '\t') {
          if (value != "") {
            return ?value;
          };
          return null;
        };
        value #= Text.fromChar(c);
        i += 1;
      };
      if (value != "") {
        return ?value;
      };
      return null;
    };
  };

  /// Parse API-Football response WITHOUT using Json.parse() to avoid memory leak
  /// Expected format: { "response": [{ "fixture": {...}, "goals": { "home": 2, "away": 1 } }] }
  public func parseApiFootball(body : Blob, _matchId : Text) : ?Score {
    // STEP 1: Test if memory leak happens before decoding
    D.print("DEBUG: parseApiFootball STEP 1 - Before decoding");
    // return ?{ home = 0; away = 0; status = #Finished }; // UNCOMMENT TO TEST

    let text = switch (Text.decodeUtf8(body)) {
      case null {
        D.print("API-Football: Failed to decode UTF8");
        return null;
      };
      case (?t) { t };
    };

    // STEP 2: Test if memory leak happens after decoding but before parsing
    D.print("DEBUG: parseApiFootball STEP 2 - After decoding, before parsing");
    // return ?{ home = 0; away = 0; status = #Finished }; // UNCOMMENT TO TEST

    // USE LIGHTWEIGHT EXTRACTION INSTEAD OF Json.parse()
    // This avoids building the full JSON tree in memory

    // Extract status
    let statusShort = switch (extractJsonValue(text, "short")) {
      case null {
        D.print("API-Football: Failed to extract status");
        return null;
      };
      case (?s) { s };
    };

    D.print("DEBUG: parseApiFootball - Extracted status without Json.parse");

    let matchStatus = parseMatchStatus(statusShort);
    D.print("API-Football: Match status: " # statusShort # " -> " # debug_show (matchStatus));

    // Extract goals
    let homeGoalText = extractJsonValue(text, "home");
    let awayGoalText = extractJsonValue(text, "away");

    let (homeScore, awayScore) = switch (homeGoalText, awayGoalText) {
      case (null, null) {
        D.print("API-Football: Goals are null, using 0-0");
        (0, 0);
      };
      case (?h, ?a) {
        // Parse the text values
        let homeVal = switch (Nat.fromText(h)) {
          case (?n) { n };
          case (null) { 0 }; // null goals in API
        };
        let awayVal = switch (Nat.fromText(a)) {
          case (?n) { n };
          case (null) { 0 }; // null goals in API
        };
        (homeVal, awayVal);
      };
      case (_, _) {
        D.print("API-Football: Inconsistent score data");
        return null;
      };
    };

    D.print("API-Football: Successfully parsed scores: " # debug_show (homeScore) # "-" # debug_show (awayScore));
    ?{ home = homeScore; away = awayScore; status = matchStatus };
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
