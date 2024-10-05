//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Logging API open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Logging API project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Logging API project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import CRT
#elseif canImport(Glibc)
#if compiler(>=6.0)
@preconcurrency import Glibc
#else
import Glibc
#endif
#elseif canImport(Musl)
import Musl
#elseif canImport(WASILibc)
import WASILibc
#else
#error("Unsupported runtime")
#endif

/// A `LoggerMain` is the central type in `SwiftLog`. Its central function is to emit log messages using one of the methods
/// corresponding to a log level.
///
/// `LoggerMain`s are value types with respect to the ``logLevel`` and the ``metadata`` (as well as the immutable `label`
/// and the selected ``LogHandler``). Therefore, `LoggerMain`s are suitable to be passed around between libraries if you want
/// to preserve metadata across libraries.
///
/// The most basic usage of a `LoggerMain` is
///
/// ```swift
/// LoggerMain.info("Hello World!")
/// ```
public struct LoggerMain {
    /// Storage class to hold the label and log handler
    @usableFromInline
    internal final class Storage: @unchecked /* and not actually */ Sendable /* but safe if only used with CoW */ {
        @usableFromInline
        var label: String

        @usableFromInline
        var handler: any LogHandler

        @inlinable
        init(label: String, handler: any LogHandler) {
            self.label = label
            self.handler = handler
        }

        @inlinable
        func copy() -> Storage {
            return Storage(label: self.label, handler: self.handler)
        }
    }

    @usableFromInline
    internal var _storage: Storage
    public var label: String {
        return self._storage.label
    }

    /// A computed property to access the `LogHandler`.
    @inlinable
    public var handler: any LogHandler {
        get {
            return self._storage.handler
        }
        set {
            if !isKnownUniquelyReferenced(&self._storage) {
                self._storage = self._storage.copy()
            }
            self._storage.handler = newValue
        }
    }

    /// The metadata provider this LoggerMain was created with.
    @inlinable
    public var metadataProvider: LoggerMain.MetadataProvider? {
        return self.handler.metadataProvider
    }

    @usableFromInline
    internal init(label: String, _ handler: any LogHandler) {
        self._storage = Storage(label: label, handler: handler)
    }
}

extension LoggerMain {
    /// Log a message passing the log level as a parameter.
    ///
    /// If the `logLevel` passed to this method is more severe than the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - level: The log level to log `message` at. For the available log levels, see `LoggerMain.Level`.
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - source: The source this log messages originates from. Defaults
    ///              to the module emitting the log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func log(level: LoggerMain.Level,
                    _ message: @autoclosure () -> LoggerMain.Message,
                    metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                    source: @autoclosure () -> String? = nil,
                    file: String = #fileID, function: String = #function, line: UInt = #line) {
        if self.logLevel <= level {
            self.handler.log(level: level,
                             message: message(),
                             metadata: metadata(),
                             source: source() ?? LoggerMain.currentModule(fileID: (file)),
                             file: file, function: function, line: line)
        }
    }

    /// Log a message passing the log level as a parameter.
    ///
    /// If the ``logLevel`` passed to this method is more severe than the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - level: The log level to log `message` at. For the available log levels, see `LoggerMain.Level`.
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func log(level: LoggerMain.Level,
                    _ message: @autoclosure () -> LoggerMain.Message,
                    metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                    file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.log(level: level, message(), metadata: metadata(), source: nil, file: file, function: function, line: line)
    }

    /// Add, change, or remove a logging metadata item.
    ///
    /// - note: Logging metadata behaves as a value that means a change to the logging metadata will only affect the
    ///         very `LoggerMain` it was changed on.
    @inlinable
    public subscript(metadataKey metadataKey: String) -> LoggerMain.Metadata.Value? {
        get {
            return self.handler[metadataKey: metadataKey]
        }
        set {
            self.handler[metadataKey: metadataKey] = newValue
        }
    }

    /// Get or set the log level configured for this `LoggerMain`.
    ///
    /// - note: `LoggerMain`s treat `logLevel` as a value. This means that a change in `logLevel` will only affect this
    ///         very `LoggerMain`. It is acceptable for logging backends to have some form of global log level override
    ///         that affects multiple or even all LoggerMains. This means a change in `logLevel` to one `LoggerMain` might in
    ///         certain cases have no effect.
    @inlinable
    public var logLevel: LoggerMain.Level {
        get {
            return self.handler.logLevel
        }
        set {
            self.handler.logLevel = newValue
        }
    }
}

extension LoggerMain {
    /// Log a message passing with the ``LoggerMain/Level/trace`` log level.
    ///
    /// If `.trace` is at least as severe as the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message
    ///    - source: The source this log messages originates from. Defaults
    ///              to the module emitting the log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func trace(_ message: @autoclosure () -> LoggerMain.Message,
                      metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                      source: @autoclosure () -> String? = nil,
                      file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.log(level: .trace, message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/trace`` log level.
    ///
    /// If `.trace` is at least as severe as the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func trace(_ message: @autoclosure () -> LoggerMain.Message,
                      metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                      file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.trace(message(), metadata: metadata(), source: nil, file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/debug`` log level.
    ///
    /// If `.debug` is at least as severe as the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - source: The source this log messages originates from. Defaults
    ///              to the module emitting the log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func debug(_ message: @autoclosure () -> LoggerMain.Message,
                      metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                      source: @autoclosure () -> String? = nil,
                      file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.log(level: .debug, message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/debug`` log level.
    ///
    /// If `.debug` is at least as severe as the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func debug(_ message: @autoclosure () -> LoggerMain.Message,
                      metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                      file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.debug(message(), metadata: metadata(), source: nil, file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/info`` log level.
    ///
    /// If `.info` is at least as severe as the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - source: The source this log messages originates from. Defaults
    ///              to the module emitting the log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func info(_ message: @autoclosure () -> LoggerMain.Message,
                     metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                     source: @autoclosure () -> String? = nil,
                     file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.log(level: .info, message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/info`` log level.
    ///
    /// If `.info` is at least as severe as the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func info(_ message: @autoclosure () -> LoggerMain.Message,
                     metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                     file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.info(message(), metadata: metadata(), source: nil, file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/notice`` log level.
    ///
    /// If `.notice` is at least as severe as the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - source: The source this log messages originates from. Defaults
    ///              to the module emitting the log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func notice(_ message: @autoclosure () -> LoggerMain.Message,
                       metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                       source: @autoclosure () -> String? = nil,
                       file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.log(level: .notice, message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/notice`` log level.
    ///
    /// If `.notice` is at least as severe as the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func notice(_ message: @autoclosure () -> LoggerMain.Message,
                       metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                       file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.notice(message(), metadata: metadata(), source: nil, file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/warning`` log level.
    ///
    /// If `.warning` is at least as severe as the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - source: The source this log messages originates from. Defaults
    ///              to the module emitting the log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func warning(_ message: @autoclosure () -> LoggerMain.Message,
                        metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                        source: @autoclosure () -> String? = nil,
                        file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.log(level: .warning, message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/warning`` log level.
    ///
    /// If `.warning` is at least as severe as the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func warning(_ message: @autoclosure () -> LoggerMain.Message,
                        metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                        file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.warning(message(), metadata: metadata(), source: nil, file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/error`` log level.
    ///
    /// If `.error` is at least as severe as the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - source: The source this log messages originates from. Defaults
    ///              to the module emitting the log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func error(_ message: @autoclosure () -> LoggerMain.Message,
                      metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                      source: @autoclosure () -> String? = nil,
                      file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.log(level: .error, message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/error`` log level.
    ///
    /// If `.error` is at least as severe as the `LoggerMain`'s ``logLevel``, it will be logged,
    /// otherwise nothing will happen.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func error(_ message: @autoclosure () -> LoggerMain.Message,
                      metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                      file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.error(message(), metadata: metadata(), source: nil, file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/critical`` log level.
    ///
    /// `.critical` messages will always be logged.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - source: The source this log messages originates from. Defaults
    ///              to the module emitting the log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func critical(_ message: @autoclosure () -> LoggerMain.Message,
                         metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                         source: @autoclosure () -> String? = nil,
                         file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.log(level: .critical, message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
    }

    /// Log a message passing with the ``LoggerMain/Level/critical`` log level.
    ///
    /// `.critical` messages will always be logged.
    ///
    /// - parameters:
    ///    - message: The message to be logged. `message` can be used with any string interpolation literal.
    ///    - metadata: One-off metadata to attach to this log message.
    ///    - file: The file this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#fileID`.
    ///    - function: The function this log message originates from (there's usually no need to pass it explicitly as
    ///                it defaults to `#function`).
    ///    - line: The line this log message originates from (there's usually no need to pass it explicitly as it
    ///            defaults to `#line`).
    @inlinable
    public func critical(_ message: @autoclosure () -> LoggerMain.Message,
                         metadata: @autoclosure () -> LoggerMain.Metadata? = nil,
                         file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.critical(message(), metadata: metadata(), source: nil, file: file, function: function, line: line)
    }
}

/// The `LoggingSystem` is a global facility where the default logging backend implementation (`LogHandler`) can be
/// configured. `LoggingSystem` is set up just once in a given program to set up the desired logging backend
/// implementation.
public enum LoggingSystem {
    private static let _factory = FactoryBox({ label, _ in StreamLogHandler.standardError(label: label) },
                                             violationErrorMesage: "logging system can only be initialized once per process.")
    private static let _metadataProviderFactory = MetadataProviderBox(nil, violationErrorMesage: "logging system can only be initialized once per process.")

    #if DEBUG
    private static let _warnOnceBox: WarnOnceBox = WarnOnceBox()
    #endif

    /// `bootstrap` is a one-time configuration function which globally selects the desired logging backend
    /// implementation. `bootstrap` can be called at maximum once in any given program, calling it more than once will
    /// lead to undefined behavior, most likely a crash.
    ///
    /// - parameters:
    ///     - factory: A closure that given a `LoggerMain` identifier, produces an instance of the `LogHandler`.
    @preconcurrency
    public static func bootstrap(_ factory: @escaping @Sendable(String) -> any LogHandler) {
        self._factory.replace({ label, _ in
            factory(label)
        }, validate: true)
    }

    /// `bootstrap` is a one-time configuration function which globally selects the desired logging backend
    /// implementation.
    ///
    /// - Warning:
    /// `bootstrap` can be called at maximum once in any given program, calling it more than once will
    /// lead to undefined behavior, most likely a crash.
    ///
    /// - parameters:
    ///     - metadataProvider: The `MetadataProvider` used to inject runtime-generated metadata from the execution context.
    ///     - factory: A closure that given a `LoggerMain` identifier, produces an instance of the `LogHandler`.
    @preconcurrency
    public static func bootstrap(_ factory: @escaping @Sendable(String, LoggerMain.MetadataProvider?) -> any LogHandler,
                                 metadataProvider: LoggerMain.MetadataProvider?) {
        self._metadataProviderFactory.replace(metadataProvider, validate: true)
        self._factory.replace(factory, validate: true)
    }

    // for our testing we want to allow multiple bootstrapping
    internal static func bootstrapInternal(_ factory: @escaping @Sendable(String) -> any LogHandler) {
        self._metadataProviderFactory.replace(nil, validate: false)
        self._factory.replace({ label, _ in
            factory(label)
        }, validate: false)
    }

    // for our testing we want to allow multiple bootstrapping
    internal static func bootstrapInternal(_ factory: @escaping @Sendable(String, LoggerMain.MetadataProvider?) -> any LogHandler,
                                           metadataProvider: LoggerMain.MetadataProvider?) {
        self._metadataProviderFactory.replace(metadataProvider, validate: false)
        self._factory.replace(factory, validate: false)
    }

    fileprivate static var factory: (String, LoggerMain.MetadataProvider?) -> any LogHandler {
        return { label, metadataProvider in
            self._factory.underlying(label, metadataProvider)
        }
    }

    /// System wide ``LoggerMain/MetadataProvider`` that was configured during the logging system's `bootstrap`.
    ///
    /// When creating a ``LoggerMain`` using the plain ``LoggerMain/init(label:)`` initializer, this metadata provider
    /// will be provided to it.
    ///
    /// When using custom log handler factories, make sure to provide the bootstrapped metadata provider to them,
    /// or the metadata will not be filled in automatically using the provider on log-sites. While using a custom
    /// factory to avoid using the bootstrapped metadata provider may sometimes be useful, usually it will lead to
    /// un-expected behavior, so make sure to always propagate it to your handlers.
    public static var metadataProvider: LoggerMain.MetadataProvider? {
        return self._metadataProviderFactory.underlying
    }

    #if DEBUG
    /// Used to warn only once about a specific ``LogHandler`` type when it does not support ``LoggerMain/MetadataProvider``,
    /// but an attempt was made to set a metadata provider on such handler. In order to avoid flooding the system with
    /// warnings such warning is only emitted in debug mode, and even then at-most once for a handler type.
    internal static func warnOnceLogHandlerNotSupportedMetadataProvider<Handler: LogHandler>(_ type: Handler.Type) -> Bool {
        self._warnOnceBox.warnOnceLogHandlerNotSupportedMetadataProvider(type: type)
    }
    #endif

    /// Protects an object such that it can only be accessed through a Reader-Writer lock.
    final class RWLockedValueBox<Value: Sendable>: @unchecked Sendable {
        private let lock = ReadWriteLock()
        private var storage: Value

        init(initialValue: Value) {
            self.storage = initialValue
        }

        func withReadLock<Result>(_ operation: (Value) -> Result) -> Result {
            self.lock.withReaderLock {
                operation(self.storage)
            }
        }

        func withWriteLock<Result>(_ operation: (inout Value) -> Result) -> Result {
            self.lock.withWriterLock {
                operation(&self.storage)
            }
        }
    }

    /// Protects an object applying the constraints that it can only be accessed through a Reader-Writer lock
    /// and can ony bre updated once from the initial value given.
    private struct ReplaceOnceBox<BoxedType: Sendable> {
        private struct ReplaceOnce: Sendable {
            private var initialized = false
            private var _underlying: BoxedType
            private let violationErrorMessage: String

            mutating func replaceUnderlying(_ underlying: BoxedType, validate: Bool) {
                precondition(!validate || !self.initialized, self.violationErrorMessage)
                self._underlying = underlying
                self.initialized = true
            }

            var underlying: BoxedType {
                return self._underlying
            }

            init(underlying: BoxedType, violationErrorMessage: String) {
                self._underlying = underlying
                self.violationErrorMessage = violationErrorMessage
            }
        }

        private let storage: RWLockedValueBox<ReplaceOnce>

        init(_ underlying: BoxedType, violationErrorMesage: String) {
            self.storage = .init(initialValue: ReplaceOnce(underlying: underlying,
                                                           violationErrorMessage: violationErrorMesage))
        }

        func replace(_ newUnderlying: BoxedType, validate: Bool) {
            self.storage.withWriteLock { $0.replaceUnderlying(newUnderlying, validate: validate) }
        }

        var underlying: BoxedType {
            self.storage.withReadLock { $0.underlying }
        }
    }

    private typealias FactoryBox = ReplaceOnceBox< @Sendable(_ label: String, _ provider: LoggerMain.MetadataProvider?) -> any LogHandler>

    private typealias MetadataProviderBox = ReplaceOnceBox<LoggerMain.MetadataProvider?>
}

extension LoggerMain {
    /// `Metadata` is a typealias for `[String: LoggerMain.MetadataValue]` the type of the metadata storage.
    public typealias Metadata = [String: MetadataValue]

    /// A logging metadata value. `LoggerMain.MetadataValue` is string, array, and dictionary literal convertible.
    ///
    /// `MetadataValue` provides convenient conformances to `ExpressibleByStringInterpolation`,
    /// `ExpressibleByStringLiteral`, `ExpressibleByArrayLiteral`, and `ExpressibleByDictionaryLiteral` which means
    /// that when constructing `MetadataValue`s you should default to using Swift's usual literals.
    ///
    /// Examples:
    ///  - prefer `LoggerMain.info("user logged in", metadata: ["user-id": "\(user.id)"])` over
    ///    `..., metadata: ["user-id": .string(user.id.description)])`
    ///  - prefer `LoggerMain.info("user selected colors", metadata: ["colors": ["\(user.topColor)", "\(user.secondColor)"]])`
    ///    over `..., metadata: ["colors": .array([.string("\(user.topColor)"), .string("\(user.secondColor)")])`
    ///  - prefer `LoggerMain.info("nested info", metadata: ["nested": ["fave-numbers": ["\(1)", "\(2)", "\(3)"], "foo": "bar"]])`
    ///    over `..., metadata: ["nested": .dictionary(["fave-numbers": ...])])`
    public enum MetadataValue {
        /// A metadata value which is a `String`.
        ///
        /// Because `MetadataValue` implements `ExpressibleByStringInterpolation`, and `ExpressibleByStringLiteral`,
        /// you don't need to type `.string(someType.description)` you can use the string interpolation `"\(someType)"`.
        case string(String)

        /// A metadata value which is some `CustomStringConvertible`.
        case stringConvertible(any CustomStringConvertible & Sendable)

        /// A metadata value which is a dictionary from `String` to `LoggerMain.MetadataValue`.
        ///
        /// Because `MetadataValue` implements `ExpressibleByDictionaryLiteral`, you don't need to type
        /// `.dictionary(["foo": .string("bar \(buz)")])`, you can just use the more natural `["foo": "bar \(buz)"]`.
        case dictionary(Metadata)

        /// A metadata value which is an array of `LoggerMain.MetadataValue`s.
        ///
        /// Because `MetadataValue` implements `ExpressibleByArrayLiteral`, you don't need to type
        /// `.array([.string("foo"), .string("bar \(buz)")])`, you can just use the more natural `["foo", "bar \(buz)"]`.
        case array([Metadata.Value])
    }

    /// The log level.
    ///
    /// Log levels are ordered by their severity, with `.trace` being the least severe and
    /// `.critical` being the most severe.
    public enum Level: String, Codable, CaseIterable {
        /// Appropriate for messages that contain information normally of use only when
        /// tracing the execution of a program.
        case trace

        /// Appropriate for messages that contain information normally of use only when
        /// debugging a program.
        case debug

        /// Appropriate for informational messages.
        case info

        /// Appropriate for conditions that are not error conditions, but that may require
        /// special handling.
        case notice

        /// Appropriate for messages that are not error conditions, but more severe than
        /// `.notice`.
        case warning

        /// Appropriate for error conditions.
        case error

        /// Appropriate for critical error conditions that usually require immediate
        /// attention.
        ///
        /// When a `critical` message is logged, the logging backend (`LogHandler`) is free to perform
        /// more heavy-weight operations to capture system state (such as capturing stack traces) to facilitate
        /// debugging.
        case critical
    }

    /// Construct a `LoggerMain` given a `label` identifying the creator of the `LoggerMain`.
    ///
    /// The `label` should identify the creator of the `LoggerMain`. This can be an application, a sub-system, or even
    /// a datatype.
    ///
    /// - parameters:
    ///     - label: An identifier for the creator of a `LoggerMain`.
    public init(label: String) {
        self.init(label: label, LoggingSystem.factory(label, LoggingSystem.metadataProvider))
    }

    /// Construct a `LoggerMain` given a `label` identifying the creator of the `LoggerMain` or a non-standard `LogHandler`.
    ///
    /// The `label` should identify the creator of the `LoggerMain`. This can be an application, a sub-system, or even
    /// a datatype.
    ///
    /// This initializer provides an escape hatch in case the global default logging backend implementation (set up
    /// using `LoggingSystem.bootstrap` is not appropriate for this particular LoggerMain.
    ///
    /// - parameters:
    ///     - label: An identifier for the creator of a `LoggerMain`.
    ///     - factory: A closure creating non-standard `LogHandler`s.
    public init(label: String, factory: (String) -> any LogHandler) {
        self = LoggerMain(label: label, factory(label))
    }

    /// Construct a `LoggerMain` given a `label` identifying the creator of the `LoggerMain` or a non-standard `LogHandler`.
    ///
    /// The `label` should identify the creator of the `LoggerMain`. This can be an application, a sub-system, or even
    /// a datatype.
    ///
    /// This initializer provides an escape hatch in case the global default logging backend implementation (set up
    /// using `LoggingSystem.bootstrap` is not appropriate for this particular LoggerMain.
    ///
    /// - parameters:
    ///     - label: An identifier for the creator of a `LoggerMain`.
    ///     - factory: A closure creating non-standard `LogHandler`s.
    public init(label: String, factory: (String, LoggerMain.MetadataProvider?) -> any LogHandler) {
        self = LoggerMain(label: label, factory(label, LoggingSystem.metadataProvider))
    }

    /// Construct a `LoggerMain` given a `label` identifying the creator of the `LoggerMain` and a non-standard ``LoggerMain/MetadataProvider``.
    ///
    /// The `label` should identify the creator of the `LoggerMain`. This can be an application, a sub-system, or even
    /// a datatype.
    ///
    /// This initializer provides an escape hatch in case the global default logging backend implementation (set up
    /// using `LoggingSystem.bootstrap` is not appropriate for this particular LoggerMain.
    ///
    /// - parameters:
    ///     - label: An identifier for the creator of a `LoggerMain`.
    ///     - metadataProvider: The custom metadata provider this LoggerMain should invoke,
    ///                         instead of the system wide bootstrapped one, when a log statement is about to be emitted.
    public init(label: String, metadataProvider: MetadataProvider) {
        self = LoggerMain(label: label, factory: { label in
            var handler = LoggingSystem.factory(label, metadataProvider)
            handler.metadataProvider = metadataProvider
            return handler
        })
    }
}

extension LoggerMain.Level {
    internal var naturalIntegralValue: Int {
        switch self {
        case .trace:
            return 0
        case .debug:
            return 1
        case .info:
            return 2
        case .notice:
            return 3
        case .warning:
            return 4
        case .error:
            return 5
        case .critical:
            return 6
        }
    }
}

extension LoggerMain.Level: Comparable {
    public static func < (lhs: LoggerMain.Level, rhs: LoggerMain.Level) -> Bool {
        return lhs.naturalIntegralValue < rhs.naturalIntegralValue
    }
}

// Extension has to be done on explicit type rather than LoggerMain.Metadata.Value as workaround for
// https://bugs.swift.org/browse/SR-9687
// Then we could write it as follows and it would work under Swift 5 and not only 4 as it does currently:
// extension LoggerMain.Metadata.Value: Equatable {
extension LoggerMain.MetadataValue: Equatable {
    public static func == (lhs: LoggerMain.Metadata.Value, rhs: LoggerMain.Metadata.Value) -> Bool {
        switch (lhs, rhs) {
        case (.string(let lhs), .string(let rhs)):
            return lhs == rhs
        case (.stringConvertible(let lhs), .stringConvertible(let rhs)):
            return lhs.description == rhs.description
        case (.array(let lhs), .array(let rhs)):
            return lhs == rhs
        case (.dictionary(let lhs), .dictionary(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

extension LoggerMain {
    /// `LoggerMain.Message` represents a log message's text. It is usually created using string literals.
    ///
    /// Example creating a `LoggerMain.Message`:
    ///
    ///     let world: String = "world"
    ///     let myLogMessage: LoggerMain.Message = "Hello \(world)"
    ///
    /// Most commonly, `LoggerMain.Message`s appear simply as the parameter to a logging method such as:
    ///
    ///     LoggerMain.info("Hello \(world)")
    ///
    public struct Message: ExpressibleByStringLiteral, Equatable, CustomStringConvertible, ExpressibleByStringInterpolation {
        public typealias StringLiteralType = String

        private var value: String

        public init(stringLiteral value: String) {
            self.value = value
        }

        public var description: String {
            return self.value
        }
    }
}

/// A pseudo-`LogHandler` that can be used to send messages to multiple other `LogHandler`s.
///
/// ### Effective LoggerMain.Level
///
/// When first initialized the multiplex log handlers' log level is automatically set to the minimum of all the
/// passed in log handlers. This ensures that each of the handlers will be able to log at their appropriate level
/// any log events they might be interested in.
///
/// Example:
/// If log handler `A` is logging at `.debug` level, and log handler `B` is logging at `.info` level, the constructed
/// `MultiplexLogHandler([A, B])`'s effective log level will be set to `.debug`, meaning that debug messages will be
/// handled by this handler, while only logged by the underlying `A` log handler (since `B`'s log level is `.info`
/// and thus it would not actually log that log message).
///
/// If the log level is _set_ on a `LoggerMain` backed by an `MultiplexLogHandler` the log level will apply to *all*
/// underlying log handlers, allowing a LoggerMain to still select at what level it wants to log regardless of if the underlying
/// handler is a multiplex or a normal one. If for some reason one might want to not allow changing a log level of a specific
/// handler passed into the multiplex log handler, this is possible by wrapping it in a handler which ignores any log level changes.
///
/// ### Effective LoggerMain.Metadata
///
/// Since a `MultiplexLogHandler` is a combination of multiple log handlers, the handling of metadata can be non-obvious.
/// For example, the underlying log handlers may have metadata of their own set before they are used to initialize the multiplex log handler.
///
/// The multiplex log handler acts purely as proxy and does not make any changes to underlying handler metadata other than
/// proxying writes that users made on a `LoggerMain` instance backed by this handler.
///
/// Setting metadata is always proxied through to _all_ underlying handlers, meaning that if a modification like
/// `LoggerMain[metadataKey: "x"] = "y"` is made, all underlying log handlers that this multiplex handler was initiated with
/// will observe this change.
///
/// Reading metadata from the multiplex log handler MAY need to pick one of conflicting values if the underlying log handlers
/// were already initiated with some metadata before passing them into the multiplex handler. The multiplex handler uses
/// the order in which the handlers were passed in during its initialization as a priority indicator - the first handler's
/// values are more important than the next handlers values, etc.
///
/// Example:
/// If the multiplex log handler was initiated with two handlers like this: `MultiplexLogHandler([handler1, handler2])`.
/// The handlers each have some already set metadata: `handler1` has metadata values for keys `one` and `all`, and `handler2`
/// has values for keys `two` and `all`.
///
/// A query through the multiplex log handler the key `one` naturally returns `handler1`'s value, and a query for `two`
/// naturally returns `handler2`'s value. Querying for the key `all` will return `handler1`'s value, as that handler was indicated
/// "more important" than the second handler. The same rule applies when querying for the `metadata` property of the
/// multiplex log handler - it constructs `Metadata` uniquing values.
public struct MultiplexLogHandler: LogHandler {
    private var handlers: [any LogHandler]
    private var effectiveLogLevel: LoggerMain.Level
    /// This metadata provider runs after all metadata providers of the multiplexed handlers.
    private var _metadataProvider: LoggerMain.MetadataProvider?

    /// Create a `MultiplexLogHandler`.
    ///
    /// - parameters:
    ///    - handlers: An array of `LogHandler`s, each of which will receive the log messages sent to this `LoggerMain`.
    ///                The array must not be empty.
    public init(_ handlers: [any LogHandler]) {
        assert(!handlers.isEmpty, "MultiplexLogHandler.handlers MUST NOT be empty")
        self.handlers = handlers
        self.effectiveLogLevel = handlers.map { $0.logLevel }.min() ?? .trace
    }

    public init(_ handlers: [any LogHandler], metadataProvider: LoggerMain.MetadataProvider?) {
        assert(!handlers.isEmpty, "MultiplexLogHandler.handlers MUST NOT be empty")
        self.handlers = handlers
        self.effectiveLogLevel = handlers.map { $0.logLevel }.min() ?? .trace
        self._metadataProvider = metadataProvider
    }

    public var logLevel: LoggerMain.Level {
        get {
            return self.effectiveLogLevel
        }
        set {
            self.mutatingForEachHandler { $0.logLevel = newValue }
            self.effectiveLogLevel = newValue
        }
    }

    public var metadataProvider: LoggerMain.MetadataProvider? {
        get {
            if self.handlers.count == 1 {
                if let innerHandler = self.handlers.first?.metadataProvider {
                    if let multiplexHandlerProvider = self._metadataProvider {
                        return .multiplex([innerHandler, multiplexHandlerProvider])
                    } else {
                        return innerHandler
                    }
                } else if let multiplexHandlerProvider = self._metadataProvider {
                    return multiplexHandlerProvider
                } else {
                    return nil
                }
            } else {
                var providers: [LoggerMain.MetadataProvider] = []
                let additionalMetadataProviderCount = (self._metadataProvider != nil ? 1 : 0)
                providers.reserveCapacity(self.handlers.count + additionalMetadataProviderCount)
                for handler in self.handlers {
                    if let provider = handler.metadataProvider {
                        providers.append(provider)
                    }
                }
                if let multiplexHandlerProvider = self._metadataProvider {
                    providers.append(multiplexHandlerProvider)
                }
                guard !providers.isEmpty else {
                    return nil
                }
                return .multiplex(providers)
            }
        }
        set {
            self.mutatingForEachHandler { $0.metadataProvider = newValue }
        }
    }

    public func log(level: LoggerMain.Level,
                    message: LoggerMain.Message,
                    metadata: LoggerMain.Metadata?,
                    source: String,
                    file: String,
                    function: String,
                    line: UInt) {
        for handler in self.handlers where handler.logLevel <= level {
            handler.log(level: level, message: message, metadata: metadata, source: source, file: file, function: function, line: line)
        }
    }

    public var metadata: LoggerMain.Metadata {
        get {
            var effective: LoggerMain.Metadata = [:]
            // as a rough estimate we assume that the underlying handlers have a similar metadata count,
            // and we use the first one's current count to estimate how big of a dictionary we need to allocate:
            effective.reserveCapacity(self.handlers.first!.metadata.count) // !-safe, we always have at least one handler

            for handler in self.handlers {
                effective.merge(handler.metadata, uniquingKeysWith: { _, handlerMetadata in handlerMetadata })
                if let provider = handler.metadataProvider {
                    effective.merge(provider.get(), uniquingKeysWith: { _, provided in provided })
                }
            }
            if let provider = self._metadataProvider {
                effective.merge(provider.get(), uniquingKeysWith: { _, provided in provided })
            }

            return effective
        }
        set {
            self.mutatingForEachHandler { $0.metadata = newValue }
        }
    }

    public subscript(metadataKey metadataKey: LoggerMain.Metadata.Key) -> LoggerMain.Metadata.Value? {
        get {
            for handler in self.handlers {
                if let value = handler[metadataKey: metadataKey] {
                    return value
                }
            }
            return nil
        }
        set {
            self.mutatingForEachHandler { $0[metadataKey: metadataKey] = newValue }
        }
    }

    private mutating func mutatingForEachHandler(_ mutator: (inout any LogHandler) -> Void) {
        for index in self.handlers.indices {
            mutator(&self.handlers[index])
        }
    }
}

#if canImport(WASILibc) || os(Android)
internal typealias CFilePointer = OpaquePointer
#else
internal typealias CFilePointer = UnsafeMutablePointer<FILE>
#endif

/// A wrapper to facilitate `print`-ing to stderr and stdio that
/// ensures access to the underlying `FILE` is locked to prevent
/// cross-thread interleaving of output.
internal struct StdioOutputStream: TextOutputStream, @unchecked Sendable {
    internal let file: CFilePointer
    internal let flushMode: FlushMode

    internal func write(_ string: String) {
        self.contiguousUTF8(string).withContiguousStorageIfAvailable { utf8Bytes in
            #if os(Windows)
            _lock_file(self.file)
            #elseif canImport(WASILibc)
            // no file locking on WASI
            #else
            flockfile(self.file)
            #endif
            defer {
                #if os(Windows)
                _unlock_file(self.file)
                #elseif canImport(WASILibc)
                // no file locking on WASI
                #else
                funlockfile(self.file)
                #endif
            }
            _ = fwrite(utf8Bytes.baseAddress!, 1, utf8Bytes.count, self.file)
            if case .always = self.flushMode {
                self.flush()
            }
        }!
    }

    /// Flush the underlying stream.
    /// This has no effect when using the `.always` flush mode, which is the default
    internal func flush() {
        _ = fflush(self.file)
    }

    internal func contiguousUTF8(_ string: String) -> String.UTF8View {
        var contiguousString = string
        contiguousString.makeContiguousUTF8()
        return contiguousString.utf8
    }

    internal static let stderr = {
        // Prevent name clashes
        #if canImport(Darwin)
        let systemStderr = Darwin.stderr
        #elseif os(Windows)
        let systemStderr = CRT.stderr
        #elseif canImport(Glibc)
        let systemStderr = Glibc.stderr!
        #elseif canImport(Musl)
        let systemStderr = Musl.stderr!
        #elseif canImport(WASILibc)
        let systemStderr = WASILibc.stderr!
        #else
        #error("Unsupported runtime")
        #endif
        return StdioOutputStream(file: systemStderr, flushMode: .always)
    }()

    internal static let stdout = {
        // Prevent name clashes
        #if canImport(Darwin)
        let systemStdout = Darwin.stdout
        #elseif os(Windows)
        let systemStdout = CRT.stdout
        #elseif canImport(Glibc)
        let systemStdout = Glibc.stdout!
        #elseif canImport(Musl)
        let systemStdout = Musl.stdout!
        #elseif canImport(WASILibc)
        let systemStdout = WASILibc.stdout!
        #else
        #error("Unsupported runtime")
        #endif
        return StdioOutputStream(file: systemStdout, flushMode: .always)
    }()

    /// Defines the flushing strategy for the underlying stream.
    internal enum FlushMode {
        case undefined
        case always
    }
}

/// `StreamLogHandler` is a simple implementation of `LogHandler` for directing
/// `LoggerMain` output to either `stderr` or `stdout` via the factory methods.
///
/// Metadata is merged in the following order:
/// 1. Metadata set on the log handler itself is used as the base metadata.
/// 2. The handler's ``metadataProvider`` is invoked, overriding any existing keys.
/// 3. The per-log-statement metadata is merged, overriding any previously set keys.
public struct StreamLogHandler: LogHandler {
    internal typealias _SendableTextOutputStream = TextOutputStream & Sendable

    /// Factory that makes a `StreamLogHandler` to directs its output to `stdout`
    public static func standardOutput(label: String) -> StreamLogHandler {
        return StreamLogHandler(label: label, stream: StdioOutputStream.stdout, metadataProvider: LoggingSystem.metadataProvider)
    }

    /// Factory that makes a `StreamLogHandler` that directs its output to `stdout`
    public static func standardOutput(label: String, metadataProvider: LoggerMain.MetadataProvider?) -> StreamLogHandler {
        return StreamLogHandler(label: label, stream: StdioOutputStream.stdout, metadataProvider: metadataProvider)
    }

    /// Factory that makes a `StreamLogHandler` that directs its output to `stderr`
    public static func standardError(label: String) -> StreamLogHandler {
        return StreamLogHandler(label: label, stream: StdioOutputStream.stderr, metadataProvider: LoggingSystem.metadataProvider)
    }

    /// Factory that makes a `StreamLogHandler` that direct its output to `stderr`
    public static func standardError(label: String, metadataProvider: LoggerMain.MetadataProvider?) -> StreamLogHandler {
        return StreamLogHandler(label: label, stream: StdioOutputStream.stderr, metadataProvider: metadataProvider)
    }

    private let stream: any _SendableTextOutputStream
    private let label: String

    public var logLevel: LoggerMain.Level = .info

    public var metadataProvider: LoggerMain.MetadataProvider?

    private var prettyMetadata: String?
    public var metadata = LoggerMain.Metadata() {
        didSet {
            self.prettyMetadata = self.prettify(self.metadata)
        }
    }

    public subscript(metadataKey metadataKey: String) -> LoggerMain.Metadata.Value? {
        get {
            return self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    // internal for testing only
    internal init(label: String, stream: any _SendableTextOutputStream) {
        self.init(label: label, stream: stream, metadataProvider: LoggingSystem.metadataProvider)
    }

    // internal for testing only
    internal init(label: String, stream: any _SendableTextOutputStream, metadataProvider: LoggerMain.MetadataProvider?) {
        self.label = label
        self.stream = stream
        self.metadataProvider = metadataProvider
    }

    public func log(level: LoggerMain.Level,
                    message: LoggerMain.Message,
                    metadata explicitMetadata: LoggerMain.Metadata?,
                    source: String,
                    file: String,
                    function: String,
                    line: UInt) {
        let effectiveMetadata = StreamLogHandler.prepareMetadata(base: self.metadata, provider: self.metadataProvider, explicit: explicitMetadata)

        let prettyMetadata: String?
        if let effectiveMetadata = effectiveMetadata {
            prettyMetadata = self.prettify(effectiveMetadata)
        } else {
            prettyMetadata = self.prettyMetadata
        }

        var stream = self.stream
        stream.write("\(self.timestamp()) \(level) \(self.label) :\(prettyMetadata.map { " \($0)" } ?? "") [\(source)] \(message)\n")
    }

    internal static func prepareMetadata(base: LoggerMain.Metadata, provider: LoggerMain.MetadataProvider?, explicit: LoggerMain.Metadata?) -> LoggerMain.Metadata? {
        var metadata = base

        let provided = provider?.get() ?? [:]

        guard !provided.isEmpty || !((explicit ?? [:]).isEmpty) else {
            // all per-log-statement values are empty
            return nil
        }

        if !provided.isEmpty {
            metadata.merge(provided, uniquingKeysWith: { _, provided in provided })
        }

        if let explicit = explicit, !explicit.isEmpty {
            metadata.merge(explicit, uniquingKeysWith: { _, explicit in explicit })
        }

        return metadata
    }

    private func prettify(_ metadata: LoggerMain.Metadata) -> String? {
        if metadata.isEmpty {
            return nil
        } else {
            return metadata.lazy.sorted(by: { $0.key < $1.key }).map { "\($0)=\($1)" }.joined(separator: " ")
        }
    }

    private func timestamp() -> String {
        var buffer = [Int8](repeating: 0, count: 255)
        #if os(Windows)
        var timestamp = __time64_t()
        _ = _time64(&timestamp)

        var localTime = tm()
        _ = _localtime64_s(&localTime, &timestamp)

        _ = strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S%z", &localTime)
        #else
        var timestamp = time(nil)
        guard let localTime = localtime(&timestamp) else {
            return "<unknown>"
        }
        strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S%z", localTime)
        #endif
        return buffer.withUnsafeBufferPointer {
            $0.withMemoryRebound(to: CChar.self) {
                String(cString: $0.baseAddress!)
            }
        }
    }
}

/// No operation LogHandler, used when no logging is required
public struct SwiftLogNoOpLogHandler: LogHandler {
    public init() {}

    public init(_: String) {}

    @inlinable public func log(level: LoggerMain.Level, message: LoggerMain.Message, metadata: LoggerMain.Metadata?, file: String, function: String, line: UInt) {}

    public func log(level: LoggerMain.Level,
                    message: LoggerMain.Message,
                    metadata: LoggerMain.Metadata?,
                    source: String,
                    file: String,
                    function: String,
                    line: UInt) {}

    @inlinable public subscript(metadataKey _: String) -> LoggerMain.Metadata.Value? {
        get {
            return nil
        }
        set {}
    }

    @inlinable public var metadata: LoggerMain.Metadata {
        get {
            return [:]
        }
        set {}
    }

    @inlinable public var logLevel: LoggerMain.Level {
        get {
            return .critical
        }
        set {}
    }
}

extension LoggerMain {
    @inlinable
    internal static func currentModule(filePath: String = #file) -> String {
        let utf8All = filePath.utf8
        return filePath.utf8.lastIndex(of: UInt8(ascii: "/")).flatMap { lastSlash -> Substring? in
            utf8All[..<lastSlash].lastIndex(of: UInt8(ascii: "/")).map { secondLastSlash -> Substring in
                filePath[utf8All.index(after: secondLastSlash) ..< lastSlash]
            }
        }.map {
            String($0)
        } ?? "n/a"
    }

    @inlinable
    internal static func currentModule(fileID: String = #fileID) -> String {
        let utf8All = fileID.utf8
        if let slashIndex = utf8All.firstIndex(of: UInt8(ascii: "/")) {
            return String(fileID[..<slashIndex])
        } else {
            return "n/a"
        }
    }
}

// Extension has to be done on explicit type rather than LoggerMain.Metadata.Value as workaround for
// https://bugs.swift.org/browse/SR-9686
extension LoggerMain.MetadataValue: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

// Extension has to be done on explicit type rather than LoggerMain.Metadata.Value as workaround for
// https://bugs.swift.org/browse/SR-9686
extension LoggerMain.MetadataValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .dictionary(let dict):
            return dict.mapValues { $0.description }.description
        case .array(let list):
            return list.map { $0.description }.description
        case .string(let str):
            return str
        case .stringConvertible(let repr):
            return repr.description
        }
    }
}

// Extension has to be done on explicit type rather than LoggerMain.Metadata.Value as workaround for
// https://bugs.swift.org/browse/SR-9687
extension LoggerMain.MetadataValue: ExpressibleByStringInterpolation {}

// Extension has to be done on explicit type rather than LoggerMain.Metadata.Value as workaround for
// https://bugs.swift.org/browse/SR-9686
extension LoggerMain.MetadataValue: ExpressibleByDictionaryLiteral {
    public typealias Key = String
    public typealias Value = LoggerMain.Metadata.Value

    public init(dictionaryLiteral elements: (String, LoggerMain.Metadata.Value)...) {
        self = .dictionary(.init(uniqueKeysWithValues: elements))
    }
}

// Extension has to be done on explicit type rather than LoggerMain.Metadata.Value as workaround for
// https://bugs.swift.org/browse/SR-9686
extension LoggerMain.MetadataValue: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = LoggerMain.Metadata.Value

    public init(arrayLiteral elements: LoggerMain.Metadata.Value...) {
        self = .array(elements)
    }
}

// MARK: - Debug only warnings

#if DEBUG
/// Contains state to manage all kinds of "warn only once" warnings which the logging system may want to issue.
private final class WarnOnceBox: @unchecked Sendable {
    private let lock: Lock = Lock()
    private var warnOnceLogHandlerNotSupportedMetadataProviderPerType = Set<ObjectIdentifier>()

    func warnOnceLogHandlerNotSupportedMetadataProvider<Handler: LogHandler>(type: Handler.Type) -> Bool {
        self.lock.withLock {
            let id = ObjectIdentifier(type)
            let (inserted, _) = warnOnceLogHandlerNotSupportedMetadataProviderPerType.insert(id)
            return inserted // warn about this handler type, it is the first time we encountered it
        }
    }
}
#endif

// MARK: - Sendable support helpers

extension LoggerMain.MetadataValue: Sendable {}
extension LoggerMain: Sendable {}
extension LoggerMain.Level: Sendable {}
extension LoggerMain.Message: Sendable {}
