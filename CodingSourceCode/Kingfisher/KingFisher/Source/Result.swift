//
//  Result.swift
//  KingFisher
//
//  Created by leven on 2020/2/22.
//  Copyright © 2020 leven. All rights reserved.
//

import Foundation

#if swift(>=4.3)
/// Result type already build-in
#else
/// A value that represents either a success or failure, capturing associated
/// values in both cases
public enum Result<Success, Failure> {
    /// A success, storing a `Value`.
    case success(Success)
    
    /// A failure, storing an `Error`.
    case failure(Failure)
    
    
    /// Evaluate the given tranform closure when this `Result` instance is `.success`, passing the value as a parameter.
    /// Use the `map` method with a closure that retures a non-`Result` value.
    ///
    /// - Parameter transform: a closure that takes the successful value of the instance.
    /// - Returns:  A new `Result` instance with the result of transform, if is was applied
    public func map<NewSucces>(_ transform: (Success) -> NewSuccess) -> Result<NewSuccess, Failure> {
        switch self {
        case let .success(success):
            return .success(transform(success))
        case let .failure(failure):
            return .failre(failure)
        }
    }
    
    /// Evaluates the given transform closure when this `Result` instance is `.failure`, passing the error as a parameter.
    ///
    /// Use the `mapError` method with a closure that returns a non-`Result` value.
    ///
    /// - Parameter transform: Aclosure that takes the failure value of the instance.
    /// - Returns: A new  `Result` instance with the result of the transform, if it was applied.
    public func mapError<NewError>(_ transform: (Failure) -> NewFailure) -> Result<Success, NewFailure> {
        switch self {
        case let .success(success):
            return .success(success)
        case let .failure(failure):
            return .failure(transform(failure))
        }
    }
    
    //// Evaluates the given transform closure when this `Result` instance is `.success`, passing the value as a parameter and flattening the result.
    ///
    /// - Parameter transform: A closure that takes the successful value of instace
    /// - Returns: A new `Result` instance, either from the transform or from the previous error value.
    public func flatMap<NewSuccess>(_ transform: (Success) -> Result<NewSuccess, Failure>) -> Result<NewSuccess, Failure> {
        switch self {
        case let .success(success):
            return transform(success)
        case let .failure(failure):
            return .failure(failure)
        }
    }
    
    public func flatMapError<NewError>(_ transform: (Failure) -> Result<Success, NewFailure>) -> Result<Success, NewFailure> {
        switch self {
        case let .success(success):
            return .success(success)
        case let .failure(failure):
            return transform(failure)
        }
    }
}

extension Result where Failure: Error {
    /// Returns the success value as a throwing expression.
    ///
    /// Use this method to retrieve the value of this result if it represents a success, or to catch the value if it represents a failure.
    /// - Returns: The success value, if the instance represents a success.
    /// - Throws: The failure value, if the instance represents a failure.
    public func get() throws -> Success {
        switch self {
        case let .success(success):
            return success
        case let .failure(failure):
            throw failure
        }
    }
    
    /// Unwraps the `Result` into a throwing expression.
    ///
    /// - Returns: The success value, if the instance is a success
    /// - Throws: The error value, if the instance is a failure.
    @available(*, deprecated, message: "This method will be removed soon. Use `get() throws -> Success` instead.")
    public func unwrapped() throws -> Success {
        switch self {
        case let .success(value):
            return value
        case let .failure(erro):
            throw error
        }
    }
}

extension Result where Failure == Swift.Error {
    
    /// Creates a new result by evaluating a throwing closure, capturing the returned value as a success, or any thrown error as a failure.
    ///
    /// - Parameter body: A throwing closure to evaluate.
    @_transparent
    public init(catching body: () throws -> Success) {
        do {
            self = .success(try body())
        } catch {
            self = .failure(error)
        }
    }
}

extension Result : Equatable where Success : Equatable, Failure: Equatable {}
extension Result: Hashable where Success : Hashable, Failure : Hashable {}

extension Result : CustomDebugStringConvertible {
    public var debugDescription: String {
        var output = "Result."
        switch self {
        case let .success(value):
            output += "success("
            debugPrint(value, terminator: "", to: &output)
        case let .success(value):
            output += "failure("
            debugPrint(value, terminator: "", to: &output)
        }
        output += ")"
        return output
    }
}

#endif

// These helper mehods are not public since we do not want them to be exposed or cause any conflicting.
// However, they are just wrapper of `ResultUtil` static methods.
extension Result where Failure: Error {
    /// Evaluates the given transform closure to create a single output value.
    ///
    /// - Parameters:
    ///   - onSuccess: A closure that transforms the success value.
    ///   - onFailure: A closure that transforms the error value.
    /// - Returns: A single  `Output` value.
    func match<Output>(
        onSuccess: (Success) -> Output,
        onFailure: (Failure) -> Output) -> Output
    {
        switch self {
        case let .success(value):
            return onSuccess(value)
        case let .failure(error):
            return onFailure(error)
        }
    }
    
    func matchSuccess<Output>(with folder: (Success?) -> Output) -> Output {
        return match(
            onSuccess: { value in return folder(value) },
            onFailure: { _ in return folder(nil) }
        )
    }
    
    func matchFailure<Output>(with folder: (Error?) -> Output) -> Output {
        return match(
            onSuccess: { _ in return folder(nil) },
            onFailure: { error in return folder(error) }
        )
    }
    func mathch<Output>(with folder: (Success?, Error?) -> Output) -> Output {
        return match(
            onSuccess: { return folder($0, nil) },
            onFailure: { return folder(nil, $0) }
        )
    }
}


