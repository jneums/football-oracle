// lib.mo - Football Oracle Library (Refactored)
import ClassPlusLib "mo:class-plus";
import MigrationTypes "migrations/types";
import MigrationLib "migrations";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import D "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Error "mo:base/Error";
import Star "mo:star/star";
import ovsfixed "mo:ovs-fixed";
import MapLib "mo:map/Map";
import SetLib "mo:map/Set";
import BTreeLib "mo:stableheapbtreemap/BTree";
import Blob "mo:base/Blob";

// Import local modules
import Service "service";
import HttpClient "http/client";
import HttpParsers "http/parsers";
import HttpTypes "http/types";
import Consensus "consensus/lib";
import ICRC3Logger "icrc3/logger";
import Json "mo:json/lib";
import Result "mo:base/Result";
import Float "mo:base/Float";

module {
  // --- Export Types for consumers ---
  public let Migration = MigrationLib;
  public let TT = MigrationLib.TimerTool;
  public let Map = MapLib;
  public let BTree = BTreeLib;
  public let Set = SetLib;
  public type State = MigrationTypes.State;
  public type CurrentState = MigrationTypes.Current.State;
  public type Environment = MigrationTypes.Current.Environment;
  public type InitArgs = MigrationTypes.Current.InitArgs;
  public type ICRC16Map = MigrationTypes.Current.ICRC16Map;

  // --- Oracle Specific Types ---
  public type OracleEvent = MigrationTypes.Current.OracleEvent;
  public type MatchRecord = MigrationTypes.Current.MatchRecord;
  public type ScheduledMatch = MigrationTypes.Current.ScheduledMatch;
  public type EventType = MigrationTypes.Current.EventType;
  public type EventData = MigrationTypes.Current.EventData;
  public type MatchOutcome = MigrationTypes.Current.MatchOutcome;
  public type ApiSource = MigrationTypes.Current.ApiSource;
  public type MatchStatus = MigrationTypes.Current.MatchStatus;
  public type ICRC16 = MigrationTypes.Current.ICRC16;
  public type Stats = MigrationTypes.Current.Stats;

  public let ICRC85_Timer_Namespace = "icrc85:ovs:shareaction:oracle";
  public let ICRC85_Payment_Namespace = "org.icdevs.libraries.oracle";

  public let init = Migration.migrate;

  public func initialState() : State { #v0_0_0(#data) };
  public let currentStateVersion = #v0_1_0(#id);

  public func natNow() : Nat { Int.abs(Time.now()) };

  public let ehash = MigrationTypes.Current.ehash;

  // --- ClassPlus Initialization ---

  public func Init<system>(
    config : {
      manager : ClassPlusLib.ClassPlusInitializationManager;
      initialState : State;
      args : ?InitArgs;
      pullEnvironment : ?(() -> Environment);
      onInitialize : ?(FootballOracle -> async* ());
      onStorageChange : ((State) -> ());
    }
  ) : () -> FootballOracle {

    D.print("Football Oracle Init");
    switch (config.pullEnvironment) {
      case (?_) {
        D.print("pull environment has value");
      };
      case (null) {
        D.print("pull environment is null");
      };
    };
    let instance = ClassPlusLib.ClassPlus<system, FootballOracle, State, InitArgs, Environment>({
      config with constructor = FootballOracle
    }).get;

    ovsfixed.initialize_cycleShare<system>({
      namespace = ICRC85_Timer_Namespace;
      icrc_85_state = instance().state.icrc85;
      wait = null;
      registerExecutionListenerAsync = instance().environment.tt.registerExecutionListenerAsync;
      setActionSync = instance().environment.tt.setActionSync;
      existingIndex = instance().environment.tt.getState().actionIdIndex;
      handler = instance().handleIcrc85Action;
    });
    instance;
  };

  // --- The Main Class ---
  public class FootballOracle(
    stored : ?State,
    instantiator : Principal,
    canister : Principal,
    _args : ?InitArgs,
    environment_passed : ?Environment,
    storageChanged : (State) -> (),
  ) {

    // --- API URLs (constants) ---
    // API-Football.com (RapidAPI) - Real endpoint
    private let API_FOOTBALL_URL = "https://v3.football.api-sports.io";
    // TheSportsDB - Free tier endpoint
    private let THESPORTSDB_URL = "https://www.thesportsdb.com/api/v1/json/3";
    // Football-Data.org - Free tier endpoint
    private let FOOTBALL_DATA_URL = "https://api.football-data.org/v4";

    // --- Core Oracle Logic ---

    /// Log an oracle event to ICRC-3
    private func logOracleEvent<system>(event : OracleEvent) : Nat {
      state.eventCounter := state.eventCounter + 1;

      switch (environment.add_record) {
        case (null) { 0 };
        case (?add_record) {
          ICRC3Logger.logEvent<system>(event, add_record);
        };
      };
    };

    // Non-stable timer ID for hourly upcoming match checks (will be restarted in postupgrade)
    var upcomingMatchCheckTimerId : ?Nat = null;

    /// Set an API key
    public func set_api_key(caller : Principal, provider : Text, key : Text) : Service.SetApiKeyResult {
      // Verify caller is admin
      if (not Principal.equal(caller, state.admin)) {
        return #Error(#Unauthorized);
      };

      // Store the API key
      Map.set(state.apiKeys, Map.thash, provider, key);
      D.print("ORACLE: Set API key for provider: " # provider);

      #Ok;
    };

    /// Set monitored leagues
    public func set_monitored_leagues(caller : Principal, leagueIds : [Nat]) : Service.SetLeaguesResult {
      // Verify caller is admin
      if (not Principal.equal(caller, state.admin)) {
        return #Error(#Unauthorized);
      };

      state.monitoredLeagues := leagueIds;
      D.print("ORACLE: Set monitored leagues: " # debug_show (leagueIds));

      #Ok;
    };

    /// Add a league to monitored leagues
    public func add_league(caller : Principal, leagueId : Nat) : Service.SetLeaguesResult {
      // Verify caller is admin
      if (not Principal.equal(caller, state.admin)) {
        return #Error(#Unauthorized);
      };

      // Check if league is already monitored
      let alreadyMonitored = Array.find<Nat>(state.monitoredLeagues, func(id) { id == leagueId });

      switch (alreadyMonitored) {
        case (?_) {
          D.print("ORACLE: League " # Nat.toText(leagueId) # " is already monitored");
          #Ok; // Already exists, return success
        };
        case (null) {
          // Add the league
          let buffer = Buffer.fromArray<Nat>(state.monitoredLeagues);
          buffer.add(leagueId);
          state.monitoredLeagues := Buffer.toArray(buffer);
          D.print("ORACLE: Added league " # Nat.toText(leagueId) # " to monitored leagues");
          #Ok;
        };
      };
    };

    /// Remove a league from monitored leagues
    public func remove_league(caller : Principal, leagueId : Nat) : Service.SetLeaguesResult {
      // Verify caller is admin
      if (not Principal.equal(caller, state.admin)) {
        return #Error(#Unauthorized);
      };

      // Filter out the league
      let filtered = Array.filter<Nat>(state.monitoredLeagues, func(id) { id != leagueId });

      if (filtered.size() == state.monitoredLeagues.size()) {
        D.print("ORACLE: League " # Nat.toText(leagueId) # " was not found in monitored leagues");
      } else {
        D.print("ORACLE: Removed league " # Nat.toText(leagueId) # " from monitored leagues");
      };

      state.monitoredLeagues := filtered;
      #Ok;
    };

    /// Get monitored leagues
    public func get_monitored_leagues() : [Nat] {
      state.monitoredLeagues;
    };

    /// Schedule a match for monitoring (manual override - normally done by discovery timer)
    public func schedule_match<system>(caller : Principal, request : Service.ScheduleMatchRequest) : async* Service.ScheduleResult {
      // Verify caller is admin
      if (not Principal.equal(caller, state.admin)) {
        return #Error(#Unauthorized);
      };

      // Validate scheduled time is in the future
      let now = natNow();
      if (request.scheduledTime < now) {
        return #Error(#InvalidTime);
      };

      // Check if already scheduled
      let apiKey = "apiFootball:" # request.apiFootballId;
      switch (Map.get(state.apiToOracleId, Map.thash, apiKey)) {
        case (?existingId) {
          D.print("ORACLE: Match already scheduled with Oracle ID: " # debug_show (existingId));
          return #Ok(existingId);
        };
        case (null) {};
      };

      // Assign new Oracle ID
      let oracleId = state.nextOracleId;
      state.nextOracleId += 1;

      D.print("ORACLE: Scheduling match with Oracle ID: " # debug_show (oracleId));

      // Create scheduled match record
      let scheduledMatch : ScheduledMatch = {
        oracleId = oracleId;
        apiFootballId = request.apiFootballId;
        scheduledTime = request.scheduledTime;
        homeTeam = request.homeTeam;
        awayTeam = request.awayTeam;
        league = request.league;
        status = #Scheduled;
        lastFetchTime = null;
        matchTimerId = null; // Will be set when match timer starts
      };

      // Store in scheduledMatches map
      Map.set(state.scheduledMatches, Map.nhash, oracleId, scheduledMatch);

      // Store API ID mapping for reverse lookup
      Map.set(state.apiToOracleId, Map.thash, apiKey, oracleId);

      // Start individual match timer
      await* start_match_timer<system>(oracleId);

      D.print("ORACLE: Match scheduled successfully with ID: " # debug_show (oracleId));
      #Ok(oracleId);
    };

    /// Fetch match data from multiple APIs with consensus validation (updated for Oracle IDs)
    public func fetch_match_data<system>(caller : Principal, oracleId : Nat) : async* Service.FetchResult {
      // Verify caller is admin
      if (not Principal.equal(caller, state.admin)) {
        return #Error(#Unauthorized);
      };

      D.print("ORACLE: Fetching match data for Oracle ID: " # debug_show (oracleId));

      // Look up the scheduled match
      let scheduledMatch = switch (Map.get(state.scheduledMatches, Map.nhash, oracleId)) {
        case (?match) { match };
        case (null) {
          return #Error(#MatchNotFound);
        };
      };

      // Get API key from state
      let apiFootballKey = switch (Map.get(state.apiKeys, Map.thash, "api_football")) {
        case (?key) { key };
        case (null) { "" };
      };

      // Track API source
      let now = natNow();

      // Fetch from API-Football
      let apiFootballResult = try {
        let url = API_FOOTBALL_URL # "/fixtures?id=" # scheduledMatch.apiFootballId;

        // Create transform context if canister is available
        let transformContext : ?HttpTypes.TransformContext = switch (environment.transform_canister) {
          case (?canister) {
            let actor_ref : actor {
              transform : shared query ({
                context : Blob;
                response : HttpTypes.HttpResponse;
              }) -> async HttpTypes.HttpResponse;
            } = actor (Principal.toText(canister));
            ?{
              function = actor_ref.transform;
              context = Blob.fromArray([]);
            };
          };
          case (null) { null };
        };

        let response = await* HttpClient.makeRequest(
          url,
          [
            { name = "x-apisports-key"; value = apiFootballKey },
          ],
          transformContext,
        );
        let bodyText = switch (Text.decodeUtf8(response.body)) {
          case null { "" };
          case (?text) { text };
        };
        D.print("API-Football response: " # bodyText);
        HttpParsers.parseApiFootball(response.body, scheduledMatch.apiFootballId);
      } catch (e) {
        D.print("API-Football error: " # Error.message(e));
        null;
      };

      // Validate match status and extract scores
      let (homeScore, awayScore, matchStatus) = switch (apiFootballResult) {
        case (?result) {
          D.print("ORACLE: API-Football result: " # debug_show (result.home) # "-" # debug_show (result.away) # " (status: " # debug_show (result.status) # ")");

          // Validate status - don't log scores for matches that haven't started
          switch (result.status) {
            case (#NotStarted) {
              D.print("ORACLE: Match hasn't started yet, ignoring score data");
              return #Error(#Generic("Match not started"));
            };
            case (#Postponed or #Cancelled or #Abandoned) {
              D.print("ORACLE: Match was postponed/cancelled/abandoned: " # debug_show (result.status));

              // Create cancellation event
              let reasonText = switch (result.status) {
                case (#Postponed) { "Postponed" };
                case (#Cancelled) { "Cancelled" };
                case (#Abandoned) { "Abandoned" };
                case (_) { "Unknown" };
              };

              let cancellationEvent : OracleEvent = {
                oracleId = oracleId;
                timestamp = now;
                eventType = #MatchCancelled;
                eventData = #MatchCancelled({
                  homeTeam = scheduledMatch.homeTeam;
                  awayTeam = scheduledMatch.awayTeam;
                  reason = reasonText;
                });
                sourceConsensus = [{
                  provider = "API-Football";
                  url = API_FOOTBALL_URL # "/fixtures?id=" # scheduledMatch.apiFootballId;
                  timestamp = now;
                }];
              };

              // Update match record to Cancelled status
              let matchRecord : MatchRecord = switch (Map.get(state.matches, Map.nhash, oracleId)) {
                case (null) {
                  {
                    oracleId = oracleId;
                    apiFootballId = scheduledMatch.apiFootballId;
                    status = #Cancelled;
                    events = [cancellationEvent];
                    lastUpdated = now;
                  };
                };
                case (?existing) {
                  {
                    oracleId = existing.oracleId;
                    apiFootballId = existing.apiFootballId;
                    status = #Cancelled;
                    events = Array.append(existing.events, [cancellationEvent]);
                    lastUpdated = now;
                  };
                };
              };
              Map.set(state.matches, Map.nhash, oracleId, matchRecord);

              // Update scheduled match status
              let updatedScheduledMatch : ScheduledMatch = {
                oracleId = scheduledMatch.oracleId;
                apiFootballId = scheduledMatch.apiFootballId;
                scheduledTime = scheduledMatch.scheduledTime;
                homeTeam = scheduledMatch.homeTeam;
                awayTeam = scheduledMatch.awayTeam;
                league = scheduledMatch.league;
                status = #Cancelled;
                lastFetchTime = ?now;
                matchTimerId = scheduledMatch.matchTimerId;
              };
              Map.set(state.scheduledMatches, Map.nhash, oracleId, updatedScheduledMatch);

              // Stop the timer to save cycles
              switch (scheduledMatch.matchTimerId) {
                case (?timerId) {
                  D.print("ORACLE: Stopping timer for cancelled match (Oracle ID: " # debug_show (oracleId) # ")");
                  Timer.cancelTimer(timerId);

                  // Clear timer ID from scheduled match
                  let finalScheduledMatch : ScheduledMatch = {
                    updatedScheduledMatch with matchTimerId = null;
                  };
                  Map.set(state.scheduledMatches, Map.nhash, oracleId, finalScheduledMatch);
                };
                case (null) {
                  D.print("ORACLE: No active timer to stop for cancelled match");
                };
              };

              // Log cancellation event to ICRC-3
              D.print("ORACLE: Logging cancellation to ICRC-3");
              let txId = logOracleEvent<system>(cancellationEvent);
              D.print("ORACLE: Cancellation logged with block index: " # debug_show (txId));

              return #Ok(txId);
            };
            case (#Unknown) {
              D.print("ORACLE: WARNING - Unknown match status, proceeding with caution");
            };
            case (#InProgress or #Finished) {
              // Valid states for logging scores
            };
          };

          (result.home, result.away, result.status);
        };
        case (null) {
          D.print("ORACLE: API fetch failed, cannot determine match status");
          return #Error(#ApiError("Failed to fetch match data"));
        };
      };

      // Determine outcome only for finished matches
      let outcome : ?MatchOutcome = switch (matchStatus) {
        case (#Finished) {
          ?(
            if (homeScore > awayScore) {
              #HomeWin;
            } else if (awayScore > homeScore) {
              #AwayWin;
            } else {
              #Draw;
            }
          );
        };
        case (_) { null }; // No outcome for in-progress or other states
      };

      // Create API source record
      let apiSource : ApiSource = {
        provider = "API-Football";
        url = API_FOOTBALL_URL # "/fixtures?id=" # scheduledMatch.apiFootballId;
        timestamp = now;
      };

      // Check if this is a new score or the first fetch
      let shouldLog = switch (Map.get(state.matches, Map.nhash, oracleId)) {
        case (null) {
          // First fetch - log if match is in progress or finished (but not if not started)
          switch (matchStatus) {
            case (#InProgress or #Finished) { true };
            case (_) { false };
          };
        };
        case (?existing) {
          // Check if there are any events
          if (existing.events.size() == 0) {
            // No events yet, log if match started
            switch (matchStatus) {
              case (#InProgress or #Finished) { true };
              case (_) { false };
            };
          } else {
            // Check if we should log based on event type and score changes
            let lastEvent = existing.events[existing.events.size() - 1];
            switch (lastEvent.eventData) {
              case (#MatchFinal(data)) {
                // Already final, only log if score changed (rare case of correction)
                data.homeScore != homeScore or data.awayScore != awayScore;
              };
              case (#MatchInProgress(data)) {
                // If match finished, ALWAYS log #MatchFinal regardless of score
                // Otherwise, only log if score changed
                switch (matchStatus) {
                  case (#Finished) { true }; // Status changed to finished - always log
                  case (#InProgress) {
                    // Still in progress, only log if score changed
                    data.homeScore != homeScore or data.awayScore != awayScore;
                  };
                  case (_) { false };
                };
              };
              case (#MatchScheduled(_)) {
                // Last event was scheduling, this is first score update - log it if match started
                switch (matchStatus) {
                  case (#InProgress or #Finished) { true };
                  case (_) { false };
                };
              };
              case (#MatchCancelled(_)) {
                // Match was cancelled, don't log anything more
                false;
              };
            };
          };
        };
      };

      // Create oracle event with Oracle ID (only if we'll log it)
      // Use different event types based on match status
      let event : OracleEvent = switch (matchStatus) {
        case (#InProgress) {
          {
            oracleId = oracleId;
            timestamp = now;
            eventType = #MatchInProgress;
            eventData = #MatchInProgress({
              homeTeam = scheduledMatch.homeTeam;
              awayTeam = scheduledMatch.awayTeam;
              homeScore = homeScore;
              awayScore = awayScore;
              minute = null; // TODO: Could extract this from API if needed
            });
            sourceConsensus = [apiSource];
          };
        };
        case (#Finished) {
          // Only create MatchFinal event if we have an outcome
          let finalOutcome = switch (outcome) {
            case (?o) { o };
            case (null) { #Draw }; // Fallback, shouldn't happen
          };
          {
            oracleId = oracleId;
            timestamp = now;
            eventType = #MatchFinal;
            eventData = #MatchFinal({
              homeTeam = scheduledMatch.homeTeam;
              awayTeam = scheduledMatch.awayTeam;
              homeScore = homeScore;
              awayScore = awayScore;
              outcome = finalOutcome;
            });
            sourceConsensus = [apiSource];
          };
        };
        case (_) {
          // Shouldn't reach here due to earlier validation, but provide a default
          {
            oracleId = oracleId;
            timestamp = now;
            eventType = #MatchInProgress;
            eventData = #MatchInProgress({
              homeTeam = scheduledMatch.homeTeam;
              awayTeam = scheduledMatch.awayTeam;
              homeScore = homeScore;
              awayScore = awayScore;
              minute = null;
            });
            sourceConsensus = [apiSource];
          };
        };
      };

      // Update match record - only append event if score changed
      let recordStatus : MatchStatus = switch (matchStatus) {
        case (#Finished) { #Final };
        case (#InProgress) { #InProgress };
        case (#Postponed or #Cancelled or #Abandoned) { #Cancelled };
        case (_) { #Scheduled }; // NotStarted or Unknown
      };

      let matchRecord : MatchRecord = switch (Map.get(state.matches, Map.nhash, oracleId)) {
        case (null) {
          {
            oracleId = oracleId;
            apiFootballId = scheduledMatch.apiFootballId;
            status = recordStatus;
            events = [event];
            lastUpdated = now;
          };
        };
        case (?existing) {
          {
            oracleId = existing.oracleId;
            apiFootballId = existing.apiFootballId;
            status = recordStatus;
            events = if (shouldLog) {
              Array.append(existing.events, [event]);
            } else {
              existing.events; // Don't add duplicate event
            };
            lastUpdated = now;
          };
        };
      };

      Map.set(state.matches, Map.nhash, oracleId, matchRecord);

      // Update scheduled match status and last fetch time
      let updatedScheduledMatch : ScheduledMatch = {
        oracleId = scheduledMatch.oracleId;
        apiFootballId = scheduledMatch.apiFootballId;
        scheduledTime = scheduledMatch.scheduledTime;
        homeTeam = scheduledMatch.homeTeam;
        awayTeam = scheduledMatch.awayTeam;
        league = scheduledMatch.league;
        status = recordStatus;
        lastFetchTime = ?now;
        matchTimerId = scheduledMatch.matchTimerId; // Will be updated by restart_match_timer
      };
      Map.set(state.scheduledMatches, Map.nhash, oracleId, updatedScheduledMatch);

      // If match is still scheduled or in progress, always restart timer
      // This ensures timer is running even after upgrades (where base Timer is lost)
      switch (recordStatus) {
        case (#Scheduled or #InProgress) {
          D.print("ORACLE: Restarting timer for Oracle ID " # debug_show (oracleId));
          await* start_match_timer<system>(oracleId);
        };
        case (_) {
          // Match is finished or cancelled, no timer needed
        };
      };

      // Log to ICRC-3 only if score changed or first fetch
      let txId = if (shouldLog) {
        D.print("ORACLE: Score changed, logging to ICRC-3");
        logOracleEvent<system>(event);
      } else {
        D.print("ORACLE: Score unchanged, skipping ICRC-3 log");
        0; // Return 0 if not logging
      };

      D.print("ORACLE: Block index returned: " # debug_show (txId));
      #Ok(txId);
    };

    /// Start discovery timer - discovers new matches from monitored leagues
    public func start_discovery_timer<system>(caller : Principal) : async* Service.StartDiscoveryResult {
      // Verify caller is admin
      if (not Principal.equal(caller, state.admin)) {
        return #Error(#Unauthorized);
      };

      // Check if already running
      switch (state.discoveryTimerId) {
        case (?_) {
          return #Error(#AlreadyRunning);
        };
        case (null) {};
      };

      D.print("ORACLE: Starting discovery timer");

      // Create recurring timer that runs daily (86400 seconds)
      let timerId = Timer.recurringTimer<system>(
        #seconds(86400), // Run once per day
        func() : async () {
          D.print("ORACLE: Discovery timer tick - checking for new matches");
          await* discover_matches<system>();
        },
      );

      state.discoveryTimerId := ?timerId;
      D.print("ORACLE: Discovery timer started with ID: " # debug_show (timerId));

      // Run discovery immediately on first start
      await* discover_matches<system>();

      #Ok;
    };

    /// Manually trigger discovery (for testing/debugging)
    public func trigger_discovery<system>(caller : Principal) : async* () {
      // Verify caller is admin
      if (not Principal.equal(caller, state.admin)) {
        return;
      };

      await* discover_matches<system>();
    };

    /// Manually trigger discovery for a specific league
    public func trigger_discovery_for_league<system>(caller : Principal, leagueId : Nat) : async* () {
      // Verify caller is admin
      if (not Principal.equal(caller, state.admin)) {
        return;
      };

      D.print("ORACLE: Triggering discovery for league: " # debug_show (leagueId));
      await* discover_matches_for_league<system>(leagueId);
    };

    /// Discover new matches for a specific league
    private func discover_matches_for_league<system>(leagueId : Nat) : async* () {
      D.print("ORACLE: Discovering matches for league: " # debug_show (leagueId));

      // Try both key formats (lowercase and original)
      let apiFootballKey = switch (Map.get(state.apiKeys, Map.thash, "api_football")) {
        case (?key) { key };
        case (null) {
          switch (Map.get(state.apiKeys, Map.thash, "API-Football")) {
            case (?key) { key };
            case (null) {
              D.print("ORACLE: No API-Football key set, skipping discovery");
              return;
            };
          };
        };
      };

      try {
        // Get upcoming fixtures (paid plan - uses "next" parameter)
        let url = API_FOOTBALL_URL # "/fixtures?league=" # Nat.toText(leagueId) # "&next=10";

        // Create transform context if canister is available
        let transformContext : ?HttpTypes.TransformContext = switch (environment.transform_canister) {
          case (?canister) {
            let actor_ref : actor {
              transform : shared query ({
                context : Blob;
                response : HttpTypes.HttpResponse;
              }) -> async HttpTypes.HttpResponse;
            } = actor (Principal.toText(canister));
            ?{
              function = actor_ref.transform;
              context = Blob.fromArray([]);
            };
          };
          case (null) { null };
        };

        let response = await* HttpClient.makeRequest(
          url,
          [
            { name = "x-apisports-key"; value = apiFootballKey },
          ],
          transformContext,
        );

        let bodyText = switch (Text.decodeUtf8(response.body)) {
          case null { "" };
          case (?text) { text };
        };

        D.print("ORACLE: Discovery response for league " # debug_show (leagueId) # ": " # bodyText);

        // Parse and schedule matches
        await* parse_and_schedule_fixtures<system>(bodyText, leagueId);

      } catch (e) {
        D.print("ORACLE: Discovery error for league " # debug_show (leagueId) # ": " # Error.message(e));
      };
    };

    /// Discover new matches from API-Football for monitored leagues
    private func discover_matches<system>() : async* () {
      D.print("ORACLE: Discovering matches for leagues: " # debug_show (state.monitoredLeagues));

      // Query each monitored league
      for (leagueId in state.monitoredLeagues.vals()) {
        await* discover_matches_for_league<system>(leagueId);
      };
    };

    /// Parse fixtures response and schedule new matches
    private func parse_and_schedule_fixtures<system>(jsonText : Text, leagueId : Nat) : async* () {
      D.print("ORACLE: Parsing fixtures response for league " # debug_show (leagueId));

      let parsed = Json.parse(jsonText);
      switch (parsed) {
        case (#err(e)) {
          D.print("ORACLE: JSON parse error: " # Json.errToText(e));
          return;
        };
        case (#ok(json)) {
          // Get the number of results
          let resultsCount = switch (Result.toOption(Json.getAsFloat(json, "results"))) {
            case null {
              D.print("ORACLE: No results field found");
              return;
            };
            case (?count) { Int.abs(Float.toInt(count)) };
          };

          D.print("ORACLE: Found " # debug_show (resultsCount) # " fixtures");

          if (resultsCount == 0) {
            D.print("ORACLE: No fixtures to schedule");
            return;
          };

          // Parse each fixture in the response array
          var index = 0;
          label fixtureLoop while (index < resultsCount) {
            let basePath = "response[" # Nat.toText(index) # "]";

            // Extract fixture ID
            let fixtureId = switch (Result.toOption(Json.getAsFloat(json, basePath # ".fixture.id"))) {
              case null {
                D.print("ORACLE: Failed to get fixture ID at index " # debug_show (index));
                index += 1;
                continue fixtureLoop;
              };
              case (?id) { Nat.toText(Int.abs(Float.toInt(id))) };
            };

            // Check if already scheduled
            let apiKey = "apiFootball:" # fixtureId;
            switch (Map.get(state.apiToOracleId, Map.thash, apiKey)) {
              case (?existingId) {
                D.print("ORACLE: Fixture " # fixtureId # " already scheduled with Oracle ID " # debug_show (existingId));
                index += 1;
                continue fixtureLoop;
              };
              case (null) {};
            };

            // Extract home team name
            let homeTeam = switch (Result.toOption(Json.getAsText(json, basePath # ".teams.home.name"))) {
              case null {
                D.print("ORACLE: Failed to get home team at index " # debug_show (index));
                index += 1;
                continue fixtureLoop;
              };
              case (?name) { name };
            };

            // Extract away team name
            let awayTeam = switch (Result.toOption(Json.getAsText(json, basePath # ".teams.away.name"))) {
              case null {
                D.print("ORACLE: Failed to get away team at index " # debug_show (index));
                index += 1;
                continue fixtureLoop;
              };
              case (?name) { name };
            };

            // Extract league name
            let leagueName = switch (Result.toOption(Json.getAsText(json, basePath # ".league.name"))) {
              case null { "League " # Nat.toText(leagueId) };
              case (?name) { name };
            };

            // Extract timestamp (Unix timestamp in seconds)
            let timestamp = switch (Result.toOption(Json.getAsFloat(json, basePath # ".fixture.timestamp"))) {
              case null {
                D.print("ORACLE: Failed to get timestamp at index " # debug_show (index));
                index += 1;
                continue fixtureLoop;
              };
              case (?ts) {
                // Convert from Unix seconds to nanoseconds
                let seconds = Int.abs(Float.toInt(ts));
                seconds * 1_000_000_000;
              };
            };

            // Validate timestamp is in the future
            let now = natNow();
            if (timestamp < now) {
              D.print("ORACLE: Fixture " # fixtureId # " is in the past, skipping");
              index += 1;
              continue fixtureLoop;
            };

            // Create new Oracle ID
            let oracleId = state.nextOracleId;
            state.nextOracleId += 1;

            // Create scheduled match
            let scheduledMatch : ScheduledMatch = {
              oracleId = oracleId;
              apiFootballId = fixtureId;
              scheduledTime = timestamp;
              homeTeam = homeTeam;
              awayTeam = awayTeam;
              league = leagueName;
              status = #Scheduled;
              lastFetchTime = null;
              matchTimerId = null;
            };

            // Store the match
            Map.set(state.scheduledMatches, Map.nhash, oracleId, scheduledMatch);
            Map.set(state.apiToOracleId, Map.thash, apiKey, oracleId);

            D.print("ORACLE: Auto-scheduled " # homeTeam # " vs " # awayTeam # " (Oracle ID: " # debug_show (oracleId) # ", Fixture ID: " # fixtureId # ")");

            // Start match timer
            await* start_match_timer<system>(oracleId);

            index += 1;
          };

          D.print("ORACLE: Finished scheduling fixtures for league " # debug_show (leagueId));
        };
      };
    };

    /// Start individual match timer - runs during match window with smart scheduling
    private func start_match_timer<system>(oracleId : Nat) : async* () {
      let match = switch (Map.get(state.scheduledMatches, Map.nhash, oracleId)) {
        case (?m) { m };
        case (null) { return };
      };

      // Cancel existing timer if any
      switch (match.matchTimerId) {
        case (?timerId) {
          Timer.cancelTimer(timerId);
        };
        case (null) {};
      };

      let now = natNow();
      let scheduledTime = match.scheduledTime;

      // OPTIMIZATION: Only start timer if match is within 2 hours of kickoff
      let twoHours : Nat = 7_200_000_000_000;
      let twoHoursBeforeKickoff = if (scheduledTime > twoHours) {
        scheduledTime - twoHours;
      } else {
        0;
      };

      // If match is more than 2 hours away, don't start timer yet
      if (now < twoHoursBeforeKickoff) {
        D.print("ORACLE: Match " # debug_show(oracleId) # " is more than 2 hours away, skipping timer");
        return;
      };

      // Start monitoring 1 hour before match
      let oneHour : Nat = 3_600_000_000_000;
      let startTime = if (scheduledTime > oneHour) {
        scheduledTime - oneHour;
      } else {
        scheduledTime;
      };

      // Match monitoring window: 3 hours after kickoff
      let threeHours : Nat = 10_800_000_000_000;
      let endTime = scheduledTime + threeHours;

      // Calculate delay until start
      let delay = if (now >= startTime) {
        0; // Start immediately
      } else {
        (startTime - now) / 1_000_000_000; // Convert to seconds
      };

      D.print("ORACLE: Setting up match timer for Oracle ID " # debug_show (oracleId) # " with delay " # debug_show (delay) # " seconds");

      // Create one-time timer to start the recurring fetch
      ignore Timer.setTimer<system>(
        #seconds(delay),
        func() : async () {
          D.print("ORACLE: Starting match monitoring for Oracle ID " # debug_show (oracleId));

          // OPTIMIZATION: Adaptive fetch interval based on match proximity
          let matchTimerId = Timer.recurringTimer<system>(
            #seconds(900), // Every 15 minutes (reduced from 10)
            func() : async () {
              let currentTime = natNow();

              // Check if match window has ended
              if (currentTime > endTime) {
                D.print("ORACLE: Match window ended for Oracle ID " # debug_show (oracleId) # ", stopping timer");

                // Get the match timer ID and cancel it
                let currentMatch = switch (Map.get(state.scheduledMatches, Map.nhash, oracleId)) {
                  case (?m) { m };
                  case (null) { return };
                };

                switch (currentMatch.matchTimerId) {
                  case (?tid) {
                    Timer.cancelTimer(tid);

                    // Update match to clear timer ID
                    let updatedMatch : ScheduledMatch = {
                      currentMatch with matchTimerId = null;
                    };
                    Map.set(state.scheduledMatches, Map.nhash, oracleId, updatedMatch);
                  };
                  case (null) {};
                };
                return;
              };

              // OPTIMIZATION: Check if match is Final and stop timer immediately
              let currentMatch = switch (Map.get(state.scheduledMatches, Map.nhash, oracleId)) {
                case (?m) { m };
                case (null) { return };
              };

              if (currentMatch.status == #Final) {
                D.print("ORACLE: Match " # debug_show(oracleId) # " is Final, stopping timer immediately");
                switch (currentMatch.matchTimerId) {
                  case (?tid) {
                    Timer.cancelTimer(tid);
                    let updatedMatch : ScheduledMatch = {
                      currentMatch with matchTimerId = null;
                    };
                    Map.set(state.scheduledMatches, Map.nhash, oracleId, updatedMatch);
                  };
                  case (null) {};
                };
                return;
              };

              // Fetch match data
              D.print("ORACLE: Match timer fetch for Oracle ID " # debug_show (oracleId));
              try {
                let _result = await* fetch_match_data<system>(state.admin, oracleId);
              } catch (e) {
                D.print("ORACLE: Match timer fetch error: " # Error.message(e));
              };
            },
          );

          // Store the timer ID
          let updatedMatch = switch (Map.get(state.scheduledMatches, Map.nhash, oracleId)) {
            case (?m) {
              {
                m with matchTimerId = ?matchTimerId;
              };
            };
            case (null) { return };
          };
          Map.set(state.scheduledMatches, Map.nhash, oracleId, updatedMatch);

          D.print("ORACLE: Match timer started with ID " # debug_show (matchTimerId));
        },
      );
    };

    /// Query all scheduled matches
    public func get_scheduled_matches() : [Service.ScheduledMatchInfo] {
      let buffer = Buffer.Buffer<Service.ScheduledMatchInfo>(Map.size(state.scheduledMatches));

      for ((oracleId, match) in Map.entries(state.scheduledMatches)) {
        let statusText = switch (match.status) {
          case (#Scheduled) { "Scheduled" };
          case (#InProgress) { "InProgress" };
          case (#Final) { "Final" };
          case (#Cancelled) { "Cancelled" };
        };

        // Get the latest event for this match (if any)
        let latestEvent = get_latest_event(oracleId);

        buffer.add({
          oracleId = oracleId;
          apiFootballId = match.apiFootballId;
          homeTeam = match.homeTeam;
          awayTeam = match.awayTeam;
          league = match.league;
          scheduledTime = match.scheduledTime;
          status = statusText;
          latestEvent = latestEvent;
        });
      };

      Buffer.toArray(buffer);
    };

    /// Query scheduled matches with filtering and pagination
    public func query_scheduled_matches(request : Service.GetScheduledMatchesRequest) : [Service.ScheduledMatchInfo] {
      let allMatches = Buffer.Buffer<Service.ScheduledMatchInfo>(Map.size(state.scheduledMatches));

      // First, collect and filter all matches
      for ((oracleId, match) in Map.entries(state.scheduledMatches)) {
        let statusText = switch (match.status) {
          case (#Scheduled) { "Scheduled" };
          case (#InProgress) { "InProgress" };
          case (#Final) { "Final" };
          case (#Cancelled) { "Cancelled" };
        };

        // Apply filters
        var include = true;

        // Filter by start time
        switch (request.startTime) {
          case (?startTime) {
            if (match.scheduledTime < startTime) {
              include := false;
            };
          };
          case (null) {};
        };

        // Filter by end time
        switch (request.endTime) {
          case (?endTime) {
            if (match.scheduledTime > endTime) {
              include := false;
            };
          };
          case (null) {};
        };

        // Filter by status
        switch (request.status) {
          case (?filterStatus) {
            if (statusText != filterStatus) {
              include := false;
            };
          };
          case (null) {};
        };

        // Filter by league
        switch (request.league) {
          case (?filterLeague) {
            if (match.league != filterLeague) {
              include := false;
            };
          };
          case (null) {};
        };

        if (include) {
          // Get the latest event for this match (if any)
          let latestEvent = get_latest_event(oracleId);

          allMatches.add({
            oracleId = oracleId;
            apiFootballId = match.apiFootballId;
            homeTeam = match.homeTeam;
            awayTeam = match.awayTeam;
            league = match.league;
            scheduledTime = match.scheduledTime;
            status = statusText;
            latestEvent = latestEvent;
          });
        };
      };

      // Sort by scheduled time (ascending)
      let sorted = Array.sort<Service.ScheduledMatchInfo>(
        Buffer.toArray(allMatches),
        func(a, b) {
          if (a.scheduledTime < b.scheduledTime) { #less } else if (a.scheduledTime > b.scheduledTime) {
            #greater;
          } else { #equal };
        },
      );

      // Apply offset and limit
      let offset = switch (request.offset) {
        case (?o) { o };
        case (null) { 0 };
      };

      let limit = switch (request.limit) {
        case (?l) { l };
        case (null) { sorted.size() };
      };

      let startIndex = Nat.min(offset, sorted.size());
      let endIndex = Nat.min(offset + limit, sorted.size());

      if (startIndex >= sorted.size()) {
        return [];
      };

      // Extract the slice
      let result = Buffer.Buffer<Service.ScheduledMatchInfo>(endIndex - startIndex);
      var i = startIndex;
      while (i < endIndex) {
        result.add(sorted[i]);
        i += 1;
      };

      Buffer.toArray(result);
    };

    /// Query all events for a match by Oracle ID
    public func get_match_events(oracleId : Nat) : Service.EventsResult {
      switch (Map.get(state.matches, Map.nhash, oracleId)) {
        case (null) { #Error(#MatchNotFound) };
        case (?record) { #Ok(record.events) };
      };
    };

    /// Query the latest event for a match by Oracle ID
    public func get_latest_event(oracleId : Nat) : ?OracleEvent {
      switch (Map.get(state.matches, Map.nhash, oracleId)) {
        case (null) { null };
        case (?record) {
          if (record.events.size() == 0) {
            null;
          } else {
            ?record.events[record.events.size() - 1];
          };
        };
      };
    };

    /// Get statistics
    public func get_stats() : MigrationTypes.Current.Stats {
      {
        totalMatches = Map.size(state.matches);
        totalEvents = state.eventCounter;
        tt = environment.tt.getStats();
        icrc85 = {
          nextCycleActionId = state.icrc85.nextCycleActionId;
          lastActionReported = state.icrc85.lastActionReported;
          activeActions = state.icrc85.activeActions;
        };
        log = [];
      };
    };

    /// Restart all active match timers (called after upgrade)
    public func restart_all_match_timers<system>() : async* () {
      D.print("ORACLE: Restarting all active match timers after upgrade");
      var restartedCount = 0;

      for ((oracleId, match) in Map.entries(state.scheduledMatches)) {
        // Only restart timers for matches that are still active
        switch (match.status) {
          case (#Scheduled or #InProgress) {
            D.print("ORACLE: Restarting timer for Oracle ID " # debug_show (oracleId) # " (status: " # debug_show (match.status) # ")");
            await* start_match_timer<system>(oracleId);
            restartedCount += 1;
          };
          case (_) {
            // Match is finished or cancelled, no timer needed
          };
        };
      };

      D.print("ORACLE: Restarted " # debug_show (restartedCount) # " match timers");
    };

    /// Check for upcoming matches and start their timers (hourly check)
    /// This ensures matches get timers started when they come within 2 hours of kickoff
    public func check_upcoming_matches<system>() : async* () {
      D.print("ORACLE: Checking for upcoming matches that need timers");
      let now = natNow();
      let twoHours : Nat = 7_200_000_000_000;
      var startedCount = 0;

      for ((oracleId, match) in Map.entries(state.scheduledMatches)) {
        // Only check scheduled or in-progress matches
        switch (match.status) {
          case (#Scheduled or #InProgress) {
            // Check if match is within 2 hours but doesn't have a timer
            let twoHoursBeforeKickoff = if (match.scheduledTime > twoHours) {
              match.scheduledTime - twoHours;
            } else {
              0;
            };

            // If we're within the 2-hour window and there's no timer, start one
            if (now >= twoHoursBeforeKickoff and match.matchTimerId == null) {
              D.print("ORACLE: Starting timer for upcoming match " # debug_show(oracleId));
              await* start_match_timer<system>(oracleId);
              startedCount += 1;
            };
          };
          case (_) {};
        };
      };

      if (startedCount > 0) {
        D.print("ORACLE: Started " # debug_show(startedCount) # " timers for upcoming matches");
      };
    };

    /// Start the hourly timer that checks for upcoming matches
    public func start_upcoming_match_check_timer<system>() : async* () {
      // Cancel existing timer if any
      switch (upcomingMatchCheckTimerId) {
        case (?timerId) {
          Timer.cancelTimer(timerId);
          D.print("ORACLE: Cancelled existing upcoming match check timer");
        };
        case (null) {};
      };

      D.print("ORACLE: Starting hourly upcoming match check timer");

      // Create recurring timer that runs every hour (3600 seconds)
      let timerId = Timer.recurringTimer<system>(
        #seconds(3600), // Every hour
        func() : async () {
          D.print("ORACLE: Hourly upcoming match check");
          await* check_upcoming_matches<system>();
        },
      );

      upcomingMatchCheckTimerId := ?timerId;
      D.print("ORACLE: Upcoming match check timer started with ID: " # debug_show (timerId));

      // Run check immediately
      await* check_upcoming_matches<system>();
    };

    // --- End core Oracle Logic ---

    public let environment = switch (environment_passed) {
      case (?val) val;
      case (null) {
        D.trap("Environment is required");
      };
    };

    let _d = environment.log.log_debug;

    public var state : CurrentState = switch (stored) {
      case (null) {
        let #v0_1_0(#data(foundState)) = init(initialState(), currentStateVersion, _args, instantiator, canister);
        foundState;
      };
      case (?val) {
        let #v0_1_0(#data(foundState)) = init(val, currentStateVersion, _args, instantiator, canister);
        foundState;
      };
    };

    storageChanged(#v0_1_0(#data(state)));

    let _self : Service.Service = actor (Principal.toText(canister));

    ///////////
    // ICRC85 ovs
    //////////
    public func handleIcrc85Action<system>(id : TT.ActionId, action : TT.Action) : async* Star.Star<TT.ActionId, TT.Error> {
      switch (action.actionType) {
        case (ICRC85_Timer_Namespace) {
          await* ovsfixed.standardShareCycles({
            icrc_85_state = state.icrc85;
            icrc_85_environment = do ? { environment.advanced!.icrc85! };
            setActionSync = environment.tt.setActionSync;
            timerNamespace = ICRC85_Timer_Namespace;
            paymentNamespace = ICRC85_Payment_Namespace;
            baseCycles = 1_000_000_000_000; // 1 XDR
            maxCycles = 100_000_000_000_000; // 1 XDR
            actionDivisor = 10000;
            actionMultiplier = 200_000_000_000; // .2 XDR
          });
          #awaited(id);
        };
        case (_) #trappable(id);
      };
    };
  };
};
