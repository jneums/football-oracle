// do not remove comments from this file
import MigrationTypes "../types";
import Time "mo:base/Time";
import v0_1_0 "types";
import D "mo:base/Debug";

module {

  // Version v0_1_0: Sets up initial oracle state for Football Oracle Service.
  // All fields initialized for safety and upgrade compatibility.
  public func upgrade(_prev_state : MigrationTypes.State, args : MigrationTypes.Args, caller : Principal, _canister : Principal) : MigrationTypes.State {
    // Extract admin from args or default to caller
    let admin = switch (args) {
      case (null) { caller };
      case (?initArgs) {
        switch (initArgs.admin) {
          case (null) { caller };
          case (?a) { a };
        };
      };
    };

    // Extract API keys from args
    let apiKeys = v0_1_0.Map.new<Text, Text>();
    switch (args) {
      case (?initArgs) {
        v0_1_0.Map.set(apiKeys, v0_1_0.Map.thash, "api_football", initArgs.api_football_key);
        v0_1_0.Map.set(apiKeys, v0_1_0.Map.thash, "thesportsdb", initArgs.thesportsdb_key);
        v0_1_0.Map.set(apiKeys, v0_1_0.Map.thash, "football_data", initArgs.football_data_key);
      };
      case (null) {};
    };

    // Initialize the v0_1_0.State record consistent with types.mo spec
    let state : v0_1_0.State = {
      icrc85 = {
        var nextCycleActionId = null;
        var lastActionReported = null;
        var activeActions = 0;
      };

      // Oracle state
      var admin = admin;
      var nextOracleId = 1; // Start IDs at 1
      var matches = v0_1_0.Map.new<Nat, v0_1_0.MatchRecord>();
      var scheduledMatches = v0_1_0.Map.new<Nat, v0_1_0.ScheduledMatch>();
      var apiToOracleId = v0_1_0.Map.new<Text, Nat>();
      var apiKeys = apiKeys;
      var eventCounter = 0;
      var discoveryTimerId = null; // Timer for discovering new matches
      var monitoredLeagues = [39]; // Default to Premier League (ID 39)
    };
    return #v0_1_0(#data(state));
  };
};
