import MigrationTypes "../types";
import D "mo:base/Debug";

module {
  public func upgrade(_prevmigration_state : MigrationTypes.State, _args : MigrationTypes.Args, _caller : Principal, _canister : Principal) : MigrationTypes.State {
    return #v0_0_0(#data);
  };
};
