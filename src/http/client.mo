// HTTP client for making outcalls
import HttpTypes "types";
import Cycles "mo:base/ExperimentalCycles";
import Blob "mo:base/Blob";
import IC "mo:ic";
import { ic } "mo:ic";

module {
  public type HttpRequest = IC.HttpRequestArgs;
  public type HttpResponse = HttpTypes.HttpResponse;
  public type HttpHeader = HttpTypes.HttpHeader;

  public type TransformFunc = shared query ({
    context : Blob;
    response : IC.HttpRequestResult;
  }) -> async IC.HttpRequestResult;

  /// Make HTTP GET request to external API
  public func makeRequest(url : Text, headers : [HttpHeader], transform : TransformFunc) : async* HttpResponse {
    let request : HttpRequest = {
      url = url;
      max_response_bytes = ?100_000; // 100KB limit - API-Football responses are typically 1-42KB
      headers = headers;
      body = null;
      method = #get;
      transform = ?{
        function = transform;
        context = Blob.fromArray([]);
      };
      is_replicated = ?false;
    };

    // Add cycles for the HTTP outcall
    // Base cost: 400M cycles + 100K cycles per KB + some overhead
    // For 100KB: The actual requirement is ~1.09B cycles based on ICP pricing
    await (with cycles = 1_200_000_000) ic.http_request(request);
  };
};
