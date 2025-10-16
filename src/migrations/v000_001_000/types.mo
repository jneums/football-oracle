// do not remove comments from this file
import Time "mo:base/Time";
import Principal "mo:base/Principal";
import OVSFixed "mo:ovs-fixed";
import TimerToolLib "mo:timer-tool";
import LogLib "mo:stable-local-log";
import MapLib "mo:map/Map";
import SetLib "mo:map/Set";
import BTreeLib "mo:stableheapbtreemap/BTree";

// please do not import any types from your project outside migrations folder here
// it can lead to bugs when you change those types later, because migration types should not be changed
// you should also avoid importing these types anywhere in your project directly from here
// use MigrationTypes.Current property instead

module {

  // do not remove the timer tool as it is essential for icrc85
  public let TimerTool = TimerToolLib;
  public let Log = LogLib;
  public let Map = MapLib;
  public let Set = SetLib;
  public let BTree = BTreeLib;

  public type ActionId = TimerToolLib.ActionId;
  public type Action = TimerToolLib.Action;
  public type ActionError = TimerToolLib.Error;

  //---------------------
  // Init Args (for upgrades/extensions)
  //---------------------
  public type InitArgs = {
    admin : ?Principal;
    api_football_key : Text;
    thesportsdb_key : Text;
    football_data_key : Text;
  };

  //---- ICRC-16 Compatible Re-exports ----
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
    #Map : [(Text, ICRC16)];
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

  //---------------
  // Football Oracle Types
  //---------------

  // Scheduled match for timer processing
  public type ScheduledMatch = {
    oracleId : Nat; // Internal Oracle ID
    apiFootballId : Text; // API-Football match ID (single source)
    scheduledTime : Nat; // When the match is scheduled to start
    homeTeam : Text;
    awayTeam : Text;
    league : Text;
    status : MatchStatus;
    lastFetchTime : ?Nat; // When we last fetched data
    matchTimerId : ?Nat; // Individual timer for this specific match
  };

  // Match outcome - MUST support draws
  public type MatchOutcome = {
    #HomeWin;
    #AwayWin;
    #Draw;
  };

  // Event types for the oracle
  public type EventType = {
    #MatchScheduled;
    #MatchInProgress;
    #MatchFinal;
    #MatchCancelled;
  };

  // Event data variants
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
      minute : ?Nat;
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

  // API source information
  public type ApiSource = {
    provider : Text;
    url : Text;
    timestamp : Nat;
  };

  // Oracle Event - the core data structure
  public type OracleEvent = {
    oracleId : Nat; // Use internal Oracle ID
    timestamp : Nat;
    eventType : EventType;
    eventData : EventData;
    sourceConsensus : [ApiSource]; // List of APIs that agreed on this data
  };

  // Match status tracking
  public type MatchStatus = {
    #Scheduled;
    #InProgress;
    #Final;
    #Cancelled;
  };

  // Match record for internal state
  public type MatchRecord = {
    oracleId : Nat; // Use internal Oracle ID
    apiFootballId : Text; // API-Football match ID (single source)
    status : MatchStatus;
    events : [OracleEvent];
    lastUpdated : Nat;
  };

  public func eventTypeEq(a : EventType, b : EventType) : Bool {
    switch (a, b) {
      case (#MatchScheduled, #MatchScheduled) true;
      case (#MatchFinal, #MatchFinal) true;
      case (#MatchInProgress, #MatchInProgress) true;
      case (#MatchCancelled, #MatchCancelled) true;
      case (_, _) false;
    };
  };

  public func eventTypeHash(a : EventType) : Nat32 {
    switch (a) {
      case (#MatchScheduled) 0;
      case (#MatchFinal) 1;
      case (#MatchInProgress) 2;
      case (#MatchCancelled) 3;
    };
  };

  public let ehash = (eventTypeHash, eventTypeEq);

  //----------------------------------
  // Oracle Service State Types
  //----------------------------------

  //--- The ICRC85 Open Value Sharing block (required infra)
  public type ICRC85Options = OVSFixed.ICRC85Environment;

  //--- Environment structure for dependency injection
  public type Environment = {
    tt : TimerToolLib.TimerTool;
    advanced : ?{
      icrc85 : ICRC85Options;
    };
    log : Log.Local_log;
    add_record : ?(<system>(ICRC16, ?ICRC16) -> Nat);
    transform_canister : ?Principal;
  };

  //--- Statistics
  public type Stats = {
    totalMatches : Nat;
    totalEvents : Nat;
    tt : TimerToolLib.Stats;
    icrc85 : {
      nextCycleActionId : ?Nat;
      lastActionReported : ?Nat;
      activeActions : Nat;
    };
    log : [Text];
  };

  ///MARK: State
  //--- Primary Oracle State
  public type State = {
    icrc85 : {
      var nextCycleActionId : ?Nat;
      var lastActionReported : ?Nat;
      var activeActions : Nat;
    };

    //-----------------
    // Oracle State
    //-----------------
    var admin : Principal;
    var nextOracleId : Nat; // Auto-incrementing internal ID
    var matches : Map.Map<Nat, MatchRecord>; // oracleId -> MatchRecord
    var scheduledMatches : Map.Map<Nat, ScheduledMatch>; // oracleId -> ScheduledMatch
    var apiToOracleId : Map.Map<Text, Nat>; // "apiFootball:12345" -> oracleId
    var apiKeys : Map.Map<Text, Text>; // provider -> api_key
    var eventCounter : Nat;
    var discoveryTimerId : ?Nat; // Timer that discovers new matches
    var monitoredLeagues : [Nat]; // League IDs to monitor (e.g., [39] for Premier League)
  };

  public type StateShared = {
    icrc85 : {
      nextCycleActionId : ?Nat;
      lastActionReported : ?Nat;
      activeActions : Nat;
    };

    // Oracle state
    admin : Principal;
    nextOracleId : Nat;
    matches : [(Nat, MatchRecord)];
    scheduledMatches : [(Nat, ScheduledMatch)];
    apiToOracleId : [(Text, Nat)];
    apiKeys : [(Text, Text)];
    eventCounter : Nat;
    discoveryTimerId : ?Nat;
    monitoredLeagues : [Nat];
  };

  public func shareState(x : State) : StateShared {
    {
      icrc85 = {
        nextCycleActionId = x.icrc85.nextCycleActionId;
        lastActionReported = x.icrc85.lastActionReported;
        activeActions = x.icrc85.activeActions;
      };

      admin = x.admin;
      nextOracleId = x.nextOracleId;
      matches = Map.toArray(x.matches);
      scheduledMatches = Map.toArray(x.scheduledMatches);
      apiToOracleId = Map.toArray(x.apiToOracleId);
      apiKeys = Map.toArray(x.apiKeys);
      eventCounter = x.eventCounter;
      discoveryTimerId = x.discoveryTimerId;
      monitoredLeagues = x.monitoredLeagues;
    };
  };
};
