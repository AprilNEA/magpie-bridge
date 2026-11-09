import Foundation
import Testing

@testable import Magpie

@Suite struct CredentialStoreTests {
    private let credential = Credential(
        baseURL: URL(string: "https://magpie.example.com")!, key: "sk-magpie-key-1")

    @Test func emptyStoreHasNothing() throws {
        let store = CredentialStore(items: MemoryKeychain(), defaults: try scratchDefaults())
        #expect(store.load() == nil)
        #expect(store.address == nil)
    }

    @Test func savedKeyIsKeyedByGatewayAddress() throws {
        let keychain = MemoryKeychain()
        let store = CredentialStore(items: keychain, defaults: try scratchDefaults())
        try store.save(credential)
        #expect(store.load() == credential)
        #expect(store.address == "https://magpie.example.com")
        #expect(keychain.items.keys.sorted() == ["https://magpie.example.com"])
    }

    @Test func forgettingKeepsAddress() throws {
        let keychain = MemoryKeychain()
        let store = CredentialStore(items: keychain, defaults: try scratchDefaults())
        try store.save(credential)
        try store.forgetKey()
        #expect(store.load() == nil)
        #expect(store.address == "https://magpie.example.com")
        #expect(keychain.items.isEmpty)
    }

    @Test func keychainFailureSurfaces() throws {
        let keychain = MemoryKeychain()
        keychain.failWith = errSecInteractionNotAllowed
        let store = CredentialStore(items: keychain, defaults: try scratchDefaults())
        #expect(throws: KeychainFailure(status: errSecInteractionNotAllowed)) {
            try store.save(credential)
        }
        #expect(store.address == nil)
    }
}

@Suite struct SessionTests {
    @Test func signInVerifiesKeyBeforeSaving() async throws {
        let keychain = MemoryKeychain()
        let store = CredentialStore(items: keychain, defaults: try scratchDefaults())
        let transport = try FakeTransport(.init(200, fixture("me")))
        let session = Session(store: store, transport: transport)
        #expect(session.credential == nil)

        try await session.signIn(address: "magpie.example.com/me", key: " sk-magpie-key-1 ")
        #expect(session.credential?.baseURL.absoluteString == "https://magpie.example.com")
        #expect(session.credential?.key == "sk-magpie-key-1")
        #expect(session.info?.name == "staff-test")
        #expect(session.refreshedAt != nil)
        #expect(store.load() == session.credential)
    }

    @Test func rejectedKeyIsNotSaved() async throws {
        let keychain = MemoryKeychain()
        let store = CredentialStore(items: keychain, defaults: try scratchDefaults())
        let transport = FakeTransport(.init(401))
        let session = Session(store: store, transport: transport)

        await #expect(throws: Session.SignInFailure.gateway(.invalidKey)) {
            try await session.signIn(address: "https://magpie.example.com", key: "sk-wrong")
        }
        #expect(session.credential == nil)
        #expect(keychain.items.isEmpty)
    }

    @Test func badAddressFailsWithoutNetwork() async throws {
        let transport = FakeTransport()
        let session = Session(
            store: CredentialStore(items: MemoryKeychain(), defaults: try scratchDefaults()),
            transport: transport)
        await #expect(throws: Session.SignInFailure.badAddress) {
            try await session.signIn(address: "ftp://x", key: "k")
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func refreshOn401ForgetsKey() async throws {
        let keychain = MemoryKeychain()
        let store = CredentialStore(items: keychain, defaults: try scratchDefaults())
        let transport = try FakeTransport(.init(200, fixture("me")), .init(401))
        let session = Session(store: store, transport: transport)
        try await session.signIn(address: "https://magpie.example.com", key: "sk-magpie-key-1")

        await session.refresh()
        #expect(session.credential == nil)
        #expect(session.info == nil)
        #expect(session.refreshedAt == nil)
        #expect(keychain.items.isEmpty)
    }

    @Test func refreshKeepsDataWhenGatewayIsDown() async throws {
        let store = CredentialStore(items: MemoryKeychain(), defaults: try scratchDefaults())
        let transport = try FakeTransport(.init(200, fixture("me")), .init(503))
        let session = Session(store: store, transport: transport)
        try await session.signIn(address: "https://magpie.example.com", key: "sk-magpie-key-1")

        await session.refresh()
        #expect(session.credential != nil)
        #expect(session.info?.name == "staff-test")
        #expect(session.refreshError == "网关返回 503。")
    }

    @Test func restoresCredentialFromStore() throws {
        let store = CredentialStore(items: MemoryKeychain(), defaults: try scratchDefaults())
        let credential = Credential(baseURL: URL(string: "http://localhost:3425")!, key: "sk-1")
        try store.save(credential)
        let session = Session(store: store, transport: FakeTransport())
        #expect(session.credential == credential)
        #expect(session.lastAddress == "http://localhost:3425")
    }
}
