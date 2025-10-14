// service.mo - Service interface for Football Oracle
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";

module {

  // ---- ICRC-16 Generic Data Type ----
  public type ICRC16Property = {
    name : Text;
    value : ICRC16;
    immutable : Bool;
  };
  public type ICRC16 = {
    #Array : [ICRC16];
    #Blob : Blob;
    #Bool : Bool;
    #Bytes : [Nat8];
    #Class : [ICRC16Property];
    #Float : Float;
    #Floats : [Float];
    #Int : Int;
    #Int16 : Int16;
    #Int32 : Int32;
    #Int64 : Int64;
    #Int8 : Int8;
    #Map : ICRC16Map;
    #ValueMap : [(ICRC16, ICRC16)];
    #Nat : Nat;
    #Nat16 : Nat16;
    #Nat32 : Nat32;
    #Nat64 : Nat64;
    #Nat8 : Nat8;
    #Nats : [Nat];
    #Option : ?ICRC16;
    #Principal : Principal;
    #Set : [ICRC16];
    #Text : Text;
  };
  public type ICRC16Map = [(Text, ICRC16)];

  // --- Match outcome types ---
  public type MatchOutcome = {
    #HomeWin;
    #AwayWin;
    #Draw;
  };

  // --- Event types ---
  public type EventType = {
    #MatchScheduled;
    #MatchFinal;
  };

  // --- Event data variants ---
  public type EventData = {
    #MatchScheduled : {
      homeTeam : Text;
      awayTeam : Text;
      scheduledTime : Nat;
    };
    #MatchFinal : {
      homeTeam : Text;
      awayTeam : Text;
      homeScore : Nat;
      awayScore : Nat;
      outcome : MatchOutcome;
    };
  };

  // --- API source information ---
  public type ApiSource = {
    provider : Text;
    url : Text;
    timestamp : Nat;
  };

  // --- Oracle Event ---
  public type OracleEvent = {
    oracleId : Nat; // Internal Oracle ID
    timestamp : Nat;
    eventType : EventType;
    eventData : EventData;
    sourceConsensus : [ApiSource];
  };

  // --- Scheduled Match Info ---
  public type ScheduledMatchInfo = {
    oracleId : Nat;
    apiFootballId : Text; // The API-Football match ID
    homeTeam : Text;
    awayTeam : Text;
    league : Text;
    scheduledTime : Nat;
    status : Text;
  };

  // --- Request Types ---
  public type FetchMatchDataRequest = {
    oracleId : Nat; // Now uses internal Oracle ID
  };

  public type ScheduleMatchRequest = {
    apiFootballId : Text; // Just the API-Football ID
    homeTeam : Text;
    awayTeam : Text;
    league : Text;
    scheduledTime : Nat;
  };

  public type SetMonitoredLeaguesRequest = {
    leagueIds : [Nat]; // API-Football league IDs to monitor
  };

  // --- Result Types ---
  public type FetchResult = {
    #Ok : Nat; // Transaction ID
    #Error : {
      #Unauthorized;
      #MatchNotFound;
      #ConsensusFailure : Text;
      #ApiError : Text;
      #Generic : Text;
    };
  };

  public type ScheduleResult = {
    #Ok : Nat; // Returns the assigned Oracle ID
    #Error : {
      #Unauthorized;
      #InvalidTime;
      #Generic : Text;
    };
  };

  public type SetApiKeyResult = {
    #Ok;
    #Error : {
      #Unauthorized;
    };
  };

  public type SetLeaguesResult = {
    #Ok;
    #Error : {
      #Unauthorized;
    };
  };

  public type StartDiscoveryResult = {
    #Ok;
    #Error : {
      #Unauthorized;
      #AlreadyRunning;
    };
  };

  public type EventsResult = {
    #Ok : [OracleEvent];
    #Error : {
      #MatchNotFound;
    };
  };

  // --- Main Service Actor Interface ---
  public type Service = actor {
    // Admin method to set monitored leagues
    set_monitored_leagues : (SetMonitoredLeaguesRequest) -> async SetLeaguesResult;

    // Admin method to start/restart discovery timer
    start_discovery_timer : () -> async StartDiscoveryResult;

    // Admin method to manually trigger fixture discovery (for testing)
    trigger_discovery : () -> async ();

    // Admin method to schedule a match for monitoring (manual override)
    schedule_match : (ScheduleMatchRequest) -> async ScheduleResult;

    // Admin method to trigger data fetch for a match
    fetch_match_data : (FetchMatchDataRequest) -> async FetchResult;

    // Public query to get all scheduled matches
    get_scheduled_matches : query () -> async [ScheduledMatchInfo];

    // Public query to get monitored leagues
    get_monitored_leagues : query () -> async [Nat];

    // Public query to get all events for a match by Oracle ID
    get_match_events : query (Nat) -> async EventsResult;

    // Query to get the latest event for a match
    get_latest_event : query (Nat) -> async ?OracleEvent;
  };
};
