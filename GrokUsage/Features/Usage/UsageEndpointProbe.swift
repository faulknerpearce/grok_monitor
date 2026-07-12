import Foundation
import os

/// Lightweight discovery helpers for documenting live endpoint responses,
/// including candidate daily-usage RPCs.
enum UsageEndpointProbe {
    private static let logger = Logger(subsystem: "com.grokusage.app", category: "Probe")

    struct ProbeResult: Sendable {
        var url: URL
        var status: Int
        var contentType: String?
        var byteCount: Int
        var preview: String
    }

    /// Candidate gRPC-web RPCs that may expose per-day usage (best-effort discovery).
    static let dailyRPCCandidates: [URL] = [
        URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokUsageInfo")!,
        URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokBuildBillingHistory")!,
        URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetUsage")!,
        URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetUsageHistory")!,
        URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetDailyUsage")!,
        URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetCreditsUsageHistory")!,
        URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetUsageByDay")!,
        URL(string: "https://grok.com/grok_api_v2.Billing/GetUsage")!,
        URL(string: "https://grok.com/grok_api_v2.UsageService/GetUsage")!,
        URL(string: "https://grok.com/grok_api_v2.UsageService/GetDailyUsage")!,
        URL(string: "https://grok.com/rest/billing/usage/daily")!,
        URL(string: "https://grok.com/rest/usage/daily")!,
        URL(string: "https://grok.com/rest/billing/usage/history")!
    ]

    static func probe(
        cookieHeader: String?,
        bearerToken: String?,
        session: URLSession = .shared
    ) async -> [ProbeResult] {
        var results: [ProbeResult] = []
        let grpcURLs = [UsageClient.billingEndpoint] + dailyRPCCandidates.filter {
            $0.path.contains("grok_api_v2")
        }
        let restURLs = UsageClient.restCandidates
            + dailyRPCCandidates.filter { !$0.path.contains("grok_api_v2") }
            + [UsageClient.cliBillingEndpoint]

        for url in grpcURLs {
            results.append(
                await probeOne(
                    url: url,
                    method: "POST",
                    grpc: true,
                    cookieHeader: cookieHeader,
                    bearerToken: bearerToken,
                    session: session
                )
            )
        }
        for url in restURLs {
            results.append(
                await probeOne(
                    url: url,
                    method: "GET",
                    grpc: false,
                    cookieHeader: cookieHeader,
                    bearerToken: bearerToken,
                    session: session
                )
            )
        }
        return results
    }

    /// Probes candidates and appends a GetGrokCreditsConfig protobuf field dump when available.
    static func probeWithFieldDump(
        cookieHeader: String?,
        bearerToken: String?,
        session: URLSession = .shared
    ) async -> (results: [ProbeResult], creditsConfigDump: String?) {
        let results = await probe(
            cookieHeader: cookieHeader,
            bearerToken: bearerToken,
            session: session
        )
        var dump: String?
        do {
            var request = URLRequest(url: UsageClient.billingEndpoint)
            request.httpMethod = "POST"
            request.httpBody = Data([0x00, 0x00, 0x00, 0x00, 0x00])
            request.timeoutInterval = 12
            request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "x-grpc-web")
            request.setValue("https://grok.com", forHTTPHeaderField: "Origin")
            request.setValue("https://grok.com/?_s=usage", forHTTPHeaderField: "Referer")
            if let bearerToken {
                request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            }
            if let cookieHeader {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty {
                dump = GRPCWebParser.debugFieldDump(data)
                logger.info("CreditsConfig field dump (\(data.count) bytes)")
            }
        } catch {
            logger.warning("CreditsConfig dump failed: \(error.localizedDescription, privacy: .public)")
        }
        return (results, dump)
    }

    private static func probeOne(
        url: URL,
        method: String,
        grpc: Bool,
        cookieHeader: String?,
        bearerToken: String?,
        session: URLSession
    ) async -> ProbeResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.httpMethod = method
        if grpc {
            request.httpBody = Data([0x00, 0x00, 0x00, 0x00, 0x00])
            request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "x-grpc-web")
            request.setValue("https://grok.com/?_s=usage", forHTTPHeaderField: "Referer")
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let cookieHeader {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        request.setValue("https://grok.com", forHTTPHeaderField: "Origin")

        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let preview: String
            if let text = String(data: data.prefix(240), encoding: .utf8) {
                preview = text
            } else {
                preview = "<binary \(data.count) bytes>"
            }
            let result = ProbeResult(
                url: url,
                status: http?.statusCode ?? -1,
                contentType: http?.value(forHTTPHeaderField: "Content-Type"),
                byteCount: data.count,
                preview: preview
            )
            logger.info("Probe \(url.absoluteString, privacy: .public) → \(result.status, privacy: .public)")
            return result
        } catch {
            return ProbeResult(
                url: url,
                status: -1,
                contentType: nil,
                byteCount: 0,
                preview: error.localizedDescription
            )
        }
    }
}
