// Football Oracle Main Canister
// This canister provides an event-sourced oracle for football match outcomes

import D "mo:base/Debug";
import Principal "mo:base/Principal";
import Timer "mo:base/Timer";
import Error "mo:base/Error";
import Nat64 "mo:base/Nat64";
import Prim "mo:⛔";
import ClassPlus "mo:class-plus";
import TT "mo:timer-tool";
import Log "mo:stable-local-log";
import ICRC3 "mo:icrc3-mo";
import Text "mo:base/Text";
import Map "mo:map/Map";
import CertTree "mo:cert/CertTree";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Char "mo:base/Char";
import Json "mo:json/lib";

// Import the local library and its service definition
import Oracle "lib";
import Service "service";
import HttpTypes "http/types";

// The main football oracle canister actor
shared (deployer) actor class FootballOracleCanister<system>(
  args : {
    oracleArgs : ?Oracle.InitArgs;
    ttArgs : ?TT.InitArgList;
  }
) = this {

  // HTTP Transform function to strip non-deterministic headers for consensus
  public query func transform(args : { context : Blob; response : HttpTypes.HttpResponse }) : async HttpTypes.HttpResponse {
    {
      args.response with headers = []; // Strip all headers for deterministic consensus
    };
  };

  // This private helper function converts the oracle value type
  // into the simpler Value type expected by the ICRC3 logger.
  private func convertOracleValueToIcrc3Value(val : Oracle.ICRC16) : ICRC3.Value {
    switch (val) {
      case (#Nat(n)) { return #Nat(n) };
      case (#Int(i)) { return #Int(i) };
      case (#Text(t)) { return #Text(t) };
      case (#Blob(b)) { return #Blob(b) };
      case (#Array(arr)) {
        let converted_arr = Array.map<Oracle.ICRC16, ICRC3.Value>(arr, convertOracleValueToIcrc3Value);
        return #Array(converted_arr);
      };
      case (#Map(map)) {
        let converted_map = Array.map<(Text, Oracle.ICRC16), (Text, ICRC3.Value)>(map, func((k, v)) { (k, convertOracleValueToIcrc3Value(v)) });
        return #Map(converted_map);
      };
      case (#Bool(b)) { return #Text(debug_show (b)) };
      case (#Principal(p)) { return #Text(Principal.toText(p)) };
      case (_) {
        return #Text("Unsupported ICRC-3 Value Type");
      };
    };
  };

  let thisPrincipal = Principal.fromActor(this);
  stable var _owner = deployer.caller;

  let initManager = ClassPlus.ClassPlusInitializationManager(_owner, thisPrincipal, true);
  let oracleInitArgs = args.oracleArgs;
  let ttInitArgs : ?TT.InitArgList = args.ttArgs;

  // --- TimerTool Setup ---
  private func reportTTExecution(execInfo : TT.ExecutionReport) : Bool {
    // MEMORY FIX: Don't log full execution reports (can be large)
    // D.print("CANISTER: TimerTool Execution: " # debug_show (execInfo));
    false;
  };
  private func reportTTError(errInfo : TT.ErrorReport) : ?Nat {
    // MEMORY FIX: Don't log full error reports (can be large)
    // D.print("CANISTER: TimerTool Error: " # debug_show (errInfo));
    null;
  };
  stable var tt_migration_state : TT.State = TT.Migration.migration.initialState;
  let tt = TT.Init<system>({
    manager = initManager;
    initialState = tt_migration_state;
    args = ttInitArgs;
    pullEnvironment = ?(
      func() : TT.Environment {
        {
          advanced = null;
          reportExecution = ?reportTTExecution;
          reportError = ?reportTTError;
          syncUnsafe = null;
          reportBatch = null;
        };
      }
    );
    onInitialize = null;
    onStorageChange = func(state : TT.State) { tt_migration_state := state };
  });

  // --- Logger Setup ---
  stable var localLog_migration_state : Log.State = Log.initialState();
  let localLog = Log.Init<system>({
    args = ?{ min_level = ?#Debug; bufferSize = ?100 }; // Reduced from 5000 to 100 to save memory
    manager = initManager;
    initialState = localLog_migration_state;
    pullEnvironment = ?(
      func() : Log.Environment {
        { tt = tt(); advanced = null; onEvict = null };
      }
    );
    onInitialize = null;
    onStorageChange = func(state : Log.State) {
      localLog_migration_state := state;
    };
  });

  // --- ICRC3 Integration ---
  stable let cert_store : CertTree.Store = CertTree.newStore();
  let ct = CertTree.Ops(cert_store);

  private func get_certificate_store() : CertTree.Store {
    cert_store;
  };

  private func updated_certification(_cert : Blob, _lastIndex : Nat) : Bool {
    ct.setCertifiedData();
    true;
  };

  private func get_icrc3_environment() : ICRC3.Environment {
    {
      updated_certification = ?updated_certification;
      get_certificate_store = ?get_certificate_store;
    };
  };

  stable var icrc3_migration_state = ICRC3.initialState();
  let icrc3 = ICRC3.Init<system>({
    manager = initManager;
    initialState = icrc3_migration_state;
    args = null;
    pullEnvironment = ?get_icrc3_environment;
    onInitialize = ?(
      func(newClass : ICRC3.ICRC3) : async* () {
        if (newClass.stats().supportedBlocks.size() == 0) {
          newClass.update_supported_blocks([
            {
              block_type = "oracle_event";
              url = "https://github.com/soccer-oracle";
            },
          ]);
        };
      }
    );
    onStorageChange = func(state : ICRC3.State) {
      icrc3_migration_state := state;
    };
  });

  // --- Football Oracle Library Setup ---
  stable var oracle_migration_state : Oracle.State = Oracle.initialState();
  let oracle = Oracle.Init<system>({
    manager = initManager;
    initialState = oracle_migration_state;
    args = oracleInitArgs;
    pullEnvironment = ?(
      func() : Oracle.Environment {
        {
          tt = tt();
          advanced = null;
          log = localLog();
          add_record = ?(
            func<system>(data : Oracle.ICRC16, meta : ?Oracle.ICRC16) : Nat {
              let converted_data = convertOracleValueToIcrc3Value(data);
              let converted_meta = Option.map(meta, convertOracleValueToIcrc3Value);
              // MEMORY FIX: Don't log full ICRC-3 records (can be very large!)
              // D.print("ORACLE: Adding record: " # debug_show ((converted_data, converted_meta)));
              icrc3().add_record<system>(converted_data, converted_meta);
            }
          );
          transform = transform;
        };
      }
    );
    onStorageChange = func(state) { oracle_migration_state := state };
    onInitialize = ?(
      func(_oracleInstance : Oracle.FootballOracle) : async* () {
        D.print("ORACLE: Initialized");
      }
    );
  });

  // --- Public API Implementation ---

  // Admin method to set an API key
  public shared (msg) func set_api_key(provider : Text, key : Text) : async Service.SetApiKeyResult {
    oracle().set_api_key(msg.caller, provider, key);
  };

  // Admin method to set monitored leagues
  public shared (msg) func set_monitored_leagues(req : Service.SetMonitoredLeaguesRequest) : async Service.SetLeaguesResult {
    oracle().set_monitored_leagues(msg.caller, req.leagueIds);
  };

  // Admin method to add a league to monitored leagues
  public shared (msg) func add_league(leagueId : Nat) : async Service.SetLeaguesResult {
    oracle().add_league(msg.caller, leagueId);
  };

  // Admin method to remove a league from monitored leagues
  public shared (msg) func remove_league(leagueId : Nat) : async Service.SetLeaguesResult {
    oracle().remove_league(msg.caller, leagueId);
  };

  // Admin method to start discovery timer
  public shared (msg) func start_discovery_timer() : async Service.StartDiscoveryResult {
    await* oracle().start_discovery_timer<system>(msg.caller);
  };

  // Admin method to manually trigger discovery (for testing)
  public shared (msg) func trigger_discovery() : async () {
    await* oracle().trigger_discovery<system>(msg.caller);
  };

  // Admin method to manually trigger discovery for a specific league
  public shared (msg) func trigger_discovery_for_league(leagueId : Nat) : async () {
    await* oracle().trigger_discovery_for_league<system>(msg.caller, leagueId);
  };

  // Admin method to schedule a match for monitoring (manual override)
  public shared (msg) func schedule_match(req : Service.ScheduleMatchRequest) : async Service.ScheduleResult {
    await* oracle().schedule_match<system>(msg.caller, req);
  };

  // Admin method to remove a scheduled match
  public shared (msg) func remove_scheduled_match(oracleId : Nat) : async Service.RemoveMatchResult {
    oracle().remove_scheduled_match(msg.caller, oracleId);
  };

  // Admin method to fetch match data by Oracle ID
  public shared (msg) func fetch_match_data(req : Service.FetchMatchDataRequest) : async Service.FetchResult {
    await* oracle().fetch_match_data<system>(msg.caller, req.oracleId);
  };

  // Admin endpoint to fetch betting odds for a match (returns raw JSON)
  public shared (msg) func fetch_odds(oracleId : Nat, bookmaker : ?Nat, bet : ?Nat) : async Text {
    await* oracle().fetch_odds<system>(msg.caller, oracleId, bookmaker, bet);
  };

  // Public query to get all scheduled matches
  public query func get_scheduled_matches() : async [Service.ScheduledMatchInfo] {
    oracle().get_scheduled_matches();
  };

  // Public query to get scheduled matches with filtering and pagination
  public query func query_scheduled_matches(request : Service.GetScheduledMatchesRequest) : async [Service.ScheduledMatchInfo] {
    oracle().query_scheduled_matches(request);
  };

  // Public query to get monitored leagues
  public query func get_monitored_leagues() : async [Nat] {
    oracle().get_monitored_leagues();
  };

  // Public query to get all events for a match by Oracle ID
  public query func get_match_events(oracleId : Nat) : async Service.EventsResult {
    oracle().get_match_events(oracleId);
  };

  // Query to get the latest event for a match by Oracle ID
  public query func get_latest_event(oracleId : Nat) : async ?Service.OracleEvent {
    oracle().get_latest_event(oracleId);
  };

  // Query to get timer diagnostics for debugging
  public query func get_timer_diagnostics(request : Service.GetTimerDiagnosticsRequest) : async Service.TimerDiagnosticsResponse {
    oracle().get_timer_diagnostics(request);
  };

  // Get oracle statistics
  public query func get_stats() : async Oracle.Stats {
    oracle().get_stats();
  };

  // Memory diagnostics endpoint
  public query func get_memory_info() : async {
    rts_memory_size : Nat;
    rts_heap_size : Nat;
    stable_memory_pages : Nat;
    stable_memory_bytes : Nat;
  } {
    // RTS metrics and stable memory diagnostics
    // Note: rts values are in machine words, stable memory in pages
    {
      rts_memory_size = Prim.rts_memory_size();
      rts_heap_size = Prim.rts_heap_size();
      stable_memory_pages = Nat64.toNat(Prim.stableMemorySize());
      stable_memory_bytes = Nat64.toNat(Prim.stableMemorySize()) * 65536; // 64KB per page
    };
  };

  // --- ICRC3 Endpoints ---
  public query func icrc3_get_blocks(args : ICRC3.GetBlocksArgs) : async ICRC3.GetBlocksResult {
    icrc3().get_blocks(args);
  };
  public query func icrc3_get_archives(args : ICRC3.GetArchivesArgs) : async ICRC3.GetArchivesResult {
    icrc3().get_archives(args);
  };
  public query func icrc3_supported_block_types() : async [ICRC3.BlockType] {
    icrc3().supported_block_types();
  };
  public query func icrc3_get_tip_certificate() : async ?ICRC3.DataCertificate {
    icrc3().get_tip_certificate();
  };
  public query func get_tip() : async ICRC3.Tip {
    icrc3().get_tip();
  };

  // --- Helper query function for tests ---
  public shared query func get_match_record(oracleId : Nat) : async ?Oracle.MatchRecord {
    switch (Map.get(oracle().state.matches, Map.nhash, oracleId)) {
      case (null) { null };
      case (?record) { ?record };
    };
  };

  // --- System Functions ---

  // Post-upgrade hook to restart all active match timers
  system func postupgrade() {
    D.print("CANISTER: Running post-upgrade hook");
    // Use a one-shot timer to restart match timers after upgrade
    // This runs after the upgrade completes
    ignore Timer.setTimer<system>(
      #seconds(1),
      func() : async () {
        try {
          D.print("CANISTER: Starting timer restart process");
          await* oracle().restart_all_match_timers<system>();
          D.print("CANISTER: Timer restart complete");

          // Also start the hourly upcoming match check timer
          D.print("CANISTER: Starting upcoming match check timer");
          await* oracle().start_upcoming_match_check_timer<system>();
          D.print("CANISTER: Upcoming match check timer started");
        } catch (e) {
          D.print("CANISTER: Error in post-upgrade: " # Error.message(e));
        };
      },
    );
  };
};
