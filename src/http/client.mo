// HTTP client for making outcalls
import HttpTypes "types";
import Cycles "mo:base/ExperimentalCycles";

module {
  public type HttpRequest = HttpTypes.HttpRequest;
  public type HttpResponse = HttpTypes.HttpResponse;
  public type HttpHeader = HttpTypes.HttpHeader;
  public type IC = HttpTypes.IC;

  /// Make HTTP GET request to external API
  public func makeRequest(url : Text, headers : [HttpHeader], transform : ?HttpTypes.TransformContext) : async* HttpResponse {
    let ic : IC = actor ("aaaaa-aa");

    let request : HttpRequest = {
      url = url;
      max_response_bytes = null; // No limit, disables consensus requirement
      headers = headers;
      body = null;
      method = #get;
      transform = transform;
    };

    // Add cycles for the HTTP outcall (21B cycles required for max_response_bytes = null)
    await (with cycles = 21_000_000_000) ic.http_request(request);
  };
};
