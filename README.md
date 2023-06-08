# genericNetworkLayer

<img width="447" alt="Screenshot 2023-06-08 at 4 55 48 PM" src="https://github.com/frodo10messi/genericNetworkLayer/assets/28492677/41b6de1b-da7a-4b2d-8416-5326289dc2b7">

``` swift
//"NetworkSession should only be responsible for making request and not decoding and signing requests")
protocol NetworkSession: AnyObject {
    func publisher<T>(_ request: URLRequest, decodingType: T.Type, token: AuthenticationJWTDTO?) -> AnyPublisher<T, APIErrorHandler> where T: Decodable
}
 
//GENERIC LAYER
//responsible for just making http request
protocol HttpClient{
    func publisher(request: URLRequest) -> AnyPublisher<(Data,HTTPURLResponse),Error>
}

extension URLSession:HttpClient{
    struct invalidHttpUrlResponse:Error{}
    
    func publisher(request: URLRequest) -> AnyPublisher<(Data, HTTPURLResponse), Error> {
        dataTaskPublisher(for: request).tryMap ({ result in
            guard let httpResponse = result.response as? HTTPURLResponse else{
                throw invalidHttpUrlResponse()
            }
            return (result.data,httpResponse)
        }).eraseToAnyPublisher()
    }
    
    
}

// we can also create generic service for apis that are generic

//you can reuse code with generics but the code should be still be able to be customized
class CountryService{
    let client:HttpClient
    
    init(client: HttpClient) {
        self.client = client
    }
    
    func loadCountries() -> AnyPublisher<[CountryDTO],Error>
    {
        
        client
            .publisher(request: LanguageCountryProvider.getCountries.makeRequest)
            .tryMap(CountryListMapper.map)
            .eraseToAnyPublisher()
    }
   
}

//FOR APIS THAT HAS generic STANDARDS FOR HTTP CODE WE CAN HAVE A genericx MAPPER

//mapping logic may change dependening on status code so i like to encapuslate the logic here
struct GenericApiMapper{
    static func map<T>(data:Data,response:HTTPURLResponse) throws -> T where T:Decodable{
        if (200..<300) ~= response.statusCode {
            return try customDateJSONDecoder.decode(T.self, from: data)
        }
        if response.statusCode == 401 {
            throw APIErrorHandler.tokenExpired
        }
        
        if let error = try? JSONDecoder().decode(ApiErrorDTO.self, from: data) {
            throw APIErrorHandler.customApiError(error)
        } else {
            throw APIErrorHandler.emptyErrorWithStatusCode(response.statusCode.description)
        }
        
    }
}

//FOR APIS THAT HAS DIFFERENT STANDARDS that require custom logic  WE CAN HAVE A CUSTOMIZED MAPPER
struct CountryListMapper{
    static func map(data:Data,response:HTTPURLResponse) throws -> [CountryDTO]{
        if (200..<300) ~= response.statusCode {
            return try customDateJSONDecoder.decode([CountryDTO].self, from: data)
        }
        
        if response.statusCode == 401 {
            throw APIErrorHandler.tokenExpired
        }
        
        if let error = try? JSONDecoder().decode(ApiErrorDTO.self, from: data) {
            throw APIErrorHandler.customApiError(error)
        } else {
            throw APIErrorHandler.emptyErrorWithStatusCode(response.statusCode.description)
        }
        
        
    }
}
//if token is variable lets say the token expires and we use refresh token then we need to provide a tokenprovider otherwise we can take a let token as dependency
class AuthenticatedHttpClientDecorator:HttpClient{
    
    let client:HttpClient
    let tokenProvider:tokenProvider
    var needAuth:(()-> Void)?
    
    init(client: HttpClient, tokenProvider: tokenProvider) {
        self.client = client
        self.tokenProvider = tokenProvider
    }
    
    func publisher(request: URLRequest) -> AnyPublisher<(Data, HTTPURLResponse), Error> {
        tokenProvider
            .tokenPublisher()
            .map { token in
                var signedRequest = request
                signedRequest.allHTTPHeaderFields?.removeValue(forKey: "Authorization")
                signedRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return signedRequest
            }
            .flatMap(client.publisher)
            .handleEvents(receiveCompletion:{[needAuth] completion in
                if case let Subscribers.Completion<Error>.failure(error) = completion,
                case APIErrorHandler.tokenExpired? = error as? APIErrorHandler {
                    needAuth?()
                }
                
            }).eraseToAnyPublisher()
            
    }
    
}

protocol tokenProvider {
    func tokenPublisher() -> AnyPublisher<AuthenticationJWTDTO,Error>
}

```

