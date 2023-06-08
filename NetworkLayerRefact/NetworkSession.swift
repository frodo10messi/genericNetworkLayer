//
//  NetworkSession.swift
//  NetworkLayerRefact
//
//

import Foundation
import Combine

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
#imageLiteral(resourceName: "Screenshot 2023-06-08 at 4.41.51 PM.png")

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
#imageLiteral(resourceName: "Screenshot 2023-06-08 at 4.45.25 PM.png")

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






extension URLSession: NetworkSession {
    func publisher<T>(_ request: URLRequest, decodingType: T.Type, token: AuthenticationJWTDTO?) -> AnyPublisher<T, APIErrorHandler> where T: Decodable {
        var newRequest = request
        newRequest.allHTTPHeaderFields?.removeValue(forKey: "Authorization")
        if let token = token?.accessToken {
            newRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        return dataTaskPublisher(for: newRequest)
            .tryMap({ result in
                guard let httpResponse = result.response as? HTTPURLResponse else {
                    throw APIErrorHandler.requestFailed
                }
                
                if (200..<300) ~= httpResponse.statusCode {
                    return result.data
                } else if httpResponse.statusCode == 401 {
                    throw APIErrorHandler.tokenExpired
                } else {
                    if let error = try? JSONDecoder().decode(ApiErrorDTO.self, from: result.data) {
                        throw APIErrorHandler.customApiError(error)
                    } else {
                        throw APIErrorHandler.emptyErrorWithStatusCode(httpResponse.statusCode.description)
                    }
                }
            })
            .decode(type: T.self, decoder: customDateJSONDecoder)
            .mapError({ error -> APIErrorHandler in
                if let error = error as? APIErrorHandler {
                    return error
                }
                return APIErrorHandler.normalError(error)
            })
            .eraseToAnyPublisher()
    }
}

private let customDateJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom(customDateDecodingStrategy)
    return decoder
}()

public func customDateDecodingStrategy(decoder: Decoder) throws -> Date {
    let container = try decoder.singleValueContainer()
    let str = try container.decode(String.self)
    return try Date.dateFromString(str)
}
