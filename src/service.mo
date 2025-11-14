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

  // --- Betting odds types ---
  public type OddValue = {
    value : Text; // "Home", "Draw", "Away"
    odd : Text; // Decimal odds as string (e.g., "1.53")
  };

  public type Bet = {
    id : Nat;
    name : Text; // e.g., "Match Winner", "Goals Over/Under"
    values : [OddValue];
  };

  public type Bookmaker = {
    id : Nat;
    name : Text; // e.g., "Bet365", "William Hill"
    bets : [Bet];
  };

  public type OddsResponse = {
    fixtureId : Nat;
    lastUpdate : Text; // ISO timestamp
    bookmakers : [Bookmaker];
  };

  public type FetchOddsResult = {
    #Ok : OddsResponse;
    #Error : Text;
  };

  // --- Match outcome types ---
  public type MatchOutcome = {
    #HomeWin;
    #AwayWin;
    #Draw;
  };

  // --- Event types ---
  public type EventType = {
    #MatchScheduled;
    #MatchInProgress;
    #MatchFinal;
    #MatchCancelled;
  };

  // --- Event data variants ---
  public type EventData = {
    #MatchScheduled : {
      homeTeam : Text;
      awayTeam : Text;
      scheduledTime : Nat;
    };
    #MatchInProgress : {
      homeTeam : Text;
      awayTeam : Text;
      homeScore : Nat;
      awayScore : Nat;
      minute : ?Nat; // Optional: minute of the match
    };
    #MatchFinal : {
      homeTeam : Text;
      awayTeam : Text;
      homeScore : Nat;
      awayScore : Nat;
      outcome : MatchOutcome;
    };
    #MatchCancelled : {
      homeTeam : Text;
      awayTeam : Text;
      reason : Text; // "Postponed", "Cancelled", or "Abandoned"
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
    latestEvent : ?OracleEvent; // Include the latest event if available (for scores, etc.)
  };

  // --- Query parameters for scheduled matches ---
  public type GetScheduledMatchesRequest = {
    startTime : ?Nat; // Optional: filter matches scheduled after this time (nanoseconds)
    endTime : ?Nat; // Optional: filter matches scheduled before this time (nanoseconds)
    status : ?Text; // Optional: filter by status ("Scheduled", "InProgress", "Final", "Cancelled")
    league : ?Text; // Optional: filter by league name
    limit : ?Nat; // Optional: maximum number of matches to return (default: all)
    offset : ?Nat; // Optional: number of matches to skip (for pagination, default: 0)
    sortBy : ?Text; // Optional: sort field ("scheduledTime" or "finishTime", default: "scheduledTime")
    sortOrder : ?Text; // Optional: sort order ("asc" or "desc", default: "asc")
  };

  // --- Request Types ---
  public type FetchMatchDataRequest = {
    oracleId : Nat; // Now uses internal Oracle ID
  };

  public type FetchOddsRequest = {
    oracleId : Nat; // Internal Oracle match ID
    bookmaker : ?Nat; // Optional: specific bookmaker ID (e.g., 8 for Bet365)
    bet : ?Nat; // Optional: specific bet type ID (e.g., 1 for Match Winner)
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

  public type RemoveMatchResult = {
    #Ok;
    #Error : {
      #Unauthorized;
      #MatchNotFound;
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

  // --- Timer Diagnostics ---
  public type GetTimerDiagnosticsRequest = {
    offset : ?Nat; // Starting index (default 0)
    limit : ?Nat; // Max results (default 50, max 100)
  };

  public type TimerDiagnostics = {
    oracleId : Nat;
    homeTeam : Text;
    awayTeam : Text;
    scheduledTime : Nat;
    status : Text; // "Scheduled", "InProgress", "Final", "Cancelled"
    hasTimer : Bool;
    timerId : ?Nat;
    hoursUntilKickoff : Float;
    hoursAfterKickoff : Float;
    shouldHaveTimer : Bool; // Based on current logic (within 2h before, up to 3h after)
    lastEventTimestamp : ?Nat;
  };

  public type TimerDiagnosticsResponse = {
    diagnostics : [TimerDiagnostics];
    total : Nat; // Total number of matches
    offset : Nat;
    limit : Nat;
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

    // Admin method to fetch betting odds for a match
    fetch_odds : (FetchOddsRequest) -> async FetchOddsResult;

    // Public query to get all scheduled matches (deprecated - use query_scheduled_matches for filtering)
    get_scheduled_matches : query () -> async [ScheduledMatchInfo];

    // Public query to get scheduled matches with filtering and pagination
    query_scheduled_matches : query (GetScheduledMatchesRequest) -> async [ScheduledMatchInfo];

    // Public query to get monitored leagues
    get_monitored_leagues : query () -> async [Nat];

    // Public query to get all events for a match by Oracle ID
    get_match_events : query (Nat) -> async EventsResult;

    // Query to get the latest event for a match
    get_latest_event : query (Nat) -> async ?OracleEvent;

    // Query to get timer diagnostics for debugging (paginated)
    get_timer_diagnostics : query (GetTimerDiagnosticsRequest) -> async TimerDiagnosticsResponse;
  };
};
