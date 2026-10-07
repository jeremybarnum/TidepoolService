//
//  TidepoolService+ConfigurationSharing.swift
//  TidepoolServiceKit
//
//  What another controller needs to upload into this user's data set: the session, the host
//  identity the data set is keyed on, and the data set itself. The session goes WITH its refresh
//  token: an access token lives minutes (12 in Tidepool's development realm), a loan lasts hours,
//  and the other controller may be out of this one's reach. Tidepool's realm does not rotate refresh
//  tokens (revokeRefreshToken false), so both controllers renew independently without either
//  invalidating the other's. The other controller never revokes it: its logout only drops the session.
//

import Foundation
import LoopKit
import TidepoolKit

extension TidepoolService: DeviceConfigurationSharing {
    public func exportConfiguration() -> SharedDeviceConfiguration {
        var state: [String: Any] = [:]
        if let session {
            let shared = TSession(environment: session.environment, accessToken: session.accessToken,
                                  accessTokenExpiration: session.accessTokenExpiration, refreshToken: session.refreshToken,
                                  userId: session.userId, username: session.username, userRoles: session.userRoles,
                                  trace: session.trace, createdDate: session.createdDate)
            state["session"] = try? JSONEncoder().encode(shared)
        }
        state["hostIdentifier"] = hostIdentifier
        state["hostVersion"] = hostVersion
        if case .fetched(let dataSetId) = dataSetIdCacheStatus {
            state["dataSetId"] = dataSetId
        }
        return SharedDeviceConfiguration(managerIdentifier: pluginIdentifier, asOf: Date(), state: state)
    }

    public convenience init?(adopting configuration: SharedDeviceConfiguration, localState: [String: Any]?) {
        guard configuration.managerIdentifier == Self.serviceIdentifier,
              let data = configuration.state["session"] as? Data,
              let session = try? JSONDecoder().decode(TSession.self, from: data),
              let hostIdentifier = configuration.state["hostIdentifier"] as? String,
              let hostVersion = configuration.state["hostVersion"] as? String else {
            return nil
        }
        self.init(hostIdentifier: hostIdentifier, hostVersion: hostVersion)
        sessionStorage = InMemorySessionStorage()
        isOnboarded = true
        isConfiguredByAnotherController = true
        if let dataSetId = configuration.state["dataSetId"] as? String {
            dataSetIdCacheStatus = .fetched(dataSetId)
        }
        self.session = session
        Task { await tapi.setSession(session) }
    }
}

/// An adopted service's session store: memory only, so this controller's keychain is never written.
private final class InMemorySessionStorage: SessionStorage {
    private var sessions: [String: TSession] = [:]
    func setSession(_ session: TSession?, for service: String) throws { sessions[service] = session }
    func getSession(for service: String) throws -> TSession? { sessions[service] }
}
