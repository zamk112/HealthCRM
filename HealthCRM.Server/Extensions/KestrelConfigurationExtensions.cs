using System.Net.Security;
using System.Runtime.InteropServices;
using System.Security.Authentication;
using Microsoft.AspNetCore.Server.Kestrel.Core;

namespace HealthCRM.Server.Extensions;

public static class KestrelConfigurationExtensions
{
    public static IWebHostBuilder ConfigureKestrelHttpsDefaults (this IWebHostBuilder webHostBuilder, IConfiguration configuration, IWebHostEnvironment hostEnvironment)
    {

        webHostBuilder.ConfigureKestrel((context, serverOptions) =>
        {

            var httpsConfiguration = configuration.GetSection("Kestrel:Server:Https");

            serverOptions.ConfigureHttpsDefaults(httpsOptions =>
            {
                if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows) && !hostEnvironment.IsDevelopment())
                    httpsOptions.SslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13;
               
                if (httpsConfiguration.GetValue<long?>("HandshakeTimeout") is long seconds)
                    httpsOptions.HandshakeTimeout = TimeSpan.FromSeconds(seconds);

                if (httpsConfiguration.GetValue<bool?>("CheckCertificateRevocation") is bool checkCertificateRevocation)
                    httpsOptions.CheckCertificateRevocation = checkCertificateRevocation;

                httpsOptions.OnAuthenticate = (connectionContext, sslOptions) =>
                {
                    sslOptions.ApplicationProtocols =
                    [
                        SslApplicationProtocol.Http2,
                        SslApplicationProtocol.Http11
                    ];

                    if (!(RuntimeInformation.IsOSPlatform(OSPlatform.Windows) || hostEnvironment.IsDevelopment()))
                    {
                        sslOptions.CipherSuitesPolicy = new CipherSuitesPolicy(
                        [
                            // TLS 1.3 cipher suites
                            TlsCipherSuite.TLS_AES_256_GCM_SHA384,
                            TlsCipherSuite.TLS_AES_128_GCM_SHA256,
                            TlsCipherSuite.TLS_CHACHA20_POLY1305_SHA256,
                            
                            // TLS 1.2 cipher suites
                            TlsCipherSuite.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
                            TlsCipherSuite.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
                            TlsCipherSuite.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256,
                        ]); 

                        sslOptions.EnabledSslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13;
                        sslOptions.EncryptionPolicy = EncryptionPolicy.RequireEncryption;
                    }
                };
            });

            serverOptions.ConfigureEndpointDefaults(endpointOptions =>
            {
                endpointOptions.Protocols = HttpProtocols.Http1AndHttp2;       
            });

            var serverLimits = httpsConfiguration.GetSection("Limits");

            if (serverLimits.GetValue<long?>("MaxConcurrentConnections") is long maxConcurrentConnections)
                 serverOptions.Limits.MaxConcurrentConnections = maxConcurrentConnections;

            if (serverLimits.GetValue<long?>("MaxRequestBodySize") is long maxRequestBodySize)
                serverOptions.Limits.MaxRequestBodySize = maxRequestBodySize;

            if (serverLimits.GetValue<long?>("MaxResponseBufferSize") is long maxResponseBufferSize)
                serverOptions.Limits.MaxResponseBufferSize = maxResponseBufferSize;

            if (serverLimits.GetValue<long?>("KeepAliveTimeout") is long keepAliveTimeout)
                serverOptions.Limits.KeepAliveTimeout = TimeSpan.FromSeconds(keepAliveTimeout);

            if (GetMinDataRate(serverLimits.GetSection("MinRequestBodyDataRate")) is { } reqRate)
                serverOptions.Limits.MinRequestBodyDataRate = reqRate;

            if (GetMinDataRate(serverLimits.GetSection("MinResponseDataRate")) is { } resRate)
                serverOptions.Limits.MinResponseDataRate = resRate;

            var http2Limits = serverLimits.GetSection("HTTP2");

            if (http2Limits.GetValue<int?>("MaxStreamsPerConnection") is int maxStreamsPerConnection)
                serverOptions.Limits.Http2.MaxStreamsPerConnection = maxStreamsPerConnection;

            if (http2Limits.GetValue<int?>("HeaderTableSize") is int headerTableSize)
                serverOptions.Limits.Http2.HeaderTableSize = headerTableSize;

            if (http2Limits.GetValue<int?>("MaxFrameSize") is int maxFrameSize)
                serverOptions.Limits.Http2.MaxFrameSize = maxFrameSize;

            if (http2Limits.GetValue<int?>("MaxRequestHeaderFieldSize") is int maxRequestHeaderFieldSize)
                serverOptions.Limits.Http2.MaxRequestHeaderFieldSize = maxRequestHeaderFieldSize;

            if (http2Limits.GetValue<int?>("InitialConnectionWindowSize") is int initialConnectionWindowSize)
                serverOptions.Limits.Http2.InitialConnectionWindowSize = initialConnectionWindowSize;

            if (http2Limits.GetValue<int?>("InitialStreamWindowSize") is int initialStreamWindowSize)
                serverOptions.Limits.Http2.InitialStreamWindowSize = initialStreamWindowSize;

            if (http2Limits.GetValue<long?>("KeepAlivePingDelay") is long keepAlivePingDelay)
                serverOptions.Limits.Http2.KeepAlivePingDelay = TimeSpan.FromSeconds(keepAlivePingDelay);

            if (http2Limits.GetValue<long?>("KeepAlivePingTimeout") is long keepAlivePingTimeout)
                serverOptions.Limits.Http2.KeepAlivePingTimeout = TimeSpan.FromSeconds(keepAlivePingTimeout);
        });

        return webHostBuilder;
        
    }

    private static MinDataRate? GetMinDataRate(IConfigurationSection section)
    {
        if (section.GetValue<double?>("BytesPerSecond") is double bytesPerSecond &&
            section.GetValue<long?>("GracePeriod") is long gracePeriod)
            return new MinDataRate(bytesPerSecond, TimeSpan.FromSeconds(gracePeriod));
        return null;
    }
}

