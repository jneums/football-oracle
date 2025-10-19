// ICRC-3 logging for oracle events
import MigrationTypes "../migrations/types";
import D "mo:base/Debug";
import Array "mo:base/Array";

module {
  public type OracleEvent = MigrationTypes.Current.OracleEvent;
  public type EventType = MigrationTypes.Current.EventType;
  public type EventData = MigrationTypes.Current.EventData;
  public type ApiSource = MigrationTypes.Current.ApiSource;
  public type MatchOutcome = MigrationTypes.Current.MatchOutcome;
  public type ICRC16Map = MigrationTypes.Current.ICRC16Map;
  public type ICRC16 = MigrationTypes.Current.ICRC16;

  /// Convert EventData to ICRC16 format
  private func eventDataToIcrc16(eventData : EventData) : ICRC16 {
    switch (eventData) {
      case (#MatchScheduled(d)) {
        #Map([
          ("type", #Text("MatchScheduled")),
          ("homeTeam", #Text(d.homeTeam)),
          ("awayTeam", #Text(d.awayTeam)),
          ("scheduledTime", #Nat(d.scheduledTime)),
        ]);
      };
      case (#MatchInProgress(d)) {
        let fields = [
          ("type", #Text("MatchInProgress")),
          ("homeTeam", #Text(d.homeTeam)),
          ("awayTeam", #Text(d.awayTeam)),
          ("homeScore", #Nat(d.homeScore)),
          ("awayScore", #Nat(d.awayScore)),
        ];
        // Add minute if available
        let withMinute = switch (d.minute) {
          case (null) { fields };
          case (?m) {
            Array.append(fields, [("minute", #Nat(m))]);
          };
        };
        #Map(withMinute);
      };
      case (#MatchFinal(d)) {
        let outcomeText = switch (d.outcome) {
          case (#HomeWin) "HomeWin";
          case (#AwayWin) "AwayWin";
          case (#Draw) "Draw";
        };
        #Map([
          ("type", #Text("MatchFinal")),
          ("homeTeam", #Text(d.homeTeam)),
          ("awayTeam", #Text(d.awayTeam)),
          ("homeScore", #Nat(d.homeScore)),
          ("awayScore", #Nat(d.awayScore)),
          ("outcome", #Text(outcomeText)),
        ]);
      };
      case (#MatchCancelled(d)) {
        #Map([
          ("type", #Text("MatchCancelled")),
          ("homeTeam", #Text(d.homeTeam)),
          ("awayTeam", #Text(d.awayTeam)),
          ("reason", #Text(d.reason)),
        ]);
      };
    };
  };

  /// Convert ApiSource array to ICRC16 format
  private func apiSourcesToIcrc16(sources : [ApiSource]) : ICRC16 {
    let mapped = Array.map<ApiSource, ICRC16>(
      sources,
      func(s : ApiSource) : ICRC16 {
        #Map([
          ("provider", #Text(s.provider)),
          ("url", #Text(s.url)),
          ("timestamp", #Nat(s.timestamp)),
        ]);
      },
    );
    #Array(mapped);
  };

  /// Log an oracle event to ICRC-3
  public func logEvent<system>(
    event : OracleEvent,
    add_record : <system>(ICRC16, ?ICRC16) -> Nat,
  ) : Nat {
    let eventTypeText = switch (event.eventType) {
      case (#MatchScheduled) "MatchScheduled";
      case (#MatchInProgress) "MatchInProgress";
      case (#MatchFinal) "MatchFinal";
      case (#MatchCancelled) "MatchCancelled";
    };

    let tx : ICRC16Map = [
      ("oracleId", #Nat(event.oracleId)), // Changed from matchId (Text) to oracleId (Nat)
      ("timestamp", #Nat(event.timestamp)),
      ("eventType", #Text(eventTypeText)),
      ("eventData", eventDataToIcrc16(event.eventData)),
      ("sourceConsensus", apiSourcesToIcrc16(event.sourceConsensus)),
    ];
    let txTop : ICRC16Map = [("btype", #Text("oracle_event"))];
    // MEMORY FIX: Don't log full ICRC-3 records (can be very large!)
    // D.print("ORACLE: Adding record: " # debug_show (#Map(tx), ?#Map(txTop)));
    let blockIndex = add_record<system>(#Map(tx), ?#Map(txTop));
    D.print("ORACLE: Block index returned: " # debug_show (blockIndex));
    blockIndex;
  };
};
