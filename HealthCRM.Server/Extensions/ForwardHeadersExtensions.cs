namespace HealthCRM.Server.Extensions;

using System.Net;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.Extensions.Options;
using Serilog;

public static class ForwardedHeadersExtensions
{
    public static IServiceCollection AddForwardHeaderOptionsConfiguration(this IServiceCollection services, IConfiguration configuration, IWebHostEnvironment hostEnvironment)
    {
        services.Configure<ForwardedHeadersOptions>(options =>
        {
            var forwardHeadersSection = configuration.GetSection("ForwardedHeaders");

            if (string.IsNullOrEmpty(forwardHeadersSection.GetValue<string>("ForwardedHeaderOptions")) && hostEnvironment.IsDevelopment())
            {
                options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
            }
            else if (!string.IsNullOrEmpty(forwardHeadersSection.GetValue<string>("ForwardedHeaderOptions")))
            {
                var forwardHeaderOptionsStr = forwardHeadersSection.GetValue<string>("ForwardedHeaderOptions")!.Trim();

                if (!string.IsNullOrEmpty(forwardHeaderOptionsStr))
                {
                    ForwardedHeaders forwardedHeaders = ForwardedHeaders.None;

                    if (forwardHeaderOptionsStr.Contains(','))
                    {
                        var forwardHeaderOptions = forwardHeaderOptionsStr.Split(",", StringSplitOptions.TrimEntries);

                        foreach (var option in forwardHeaderOptions)
                        {
                            forwardedHeaders |= Enum.Parse<ForwardedHeaders>(option);
                        }
                    }
                    else
                    {
                        forwardedHeaders = Enum.Parse<ForwardedHeaders>(forwardHeaderOptionsStr);
                    }

                    options.ForwardedHeaders = forwardedHeaders;
                }
                else
                {
                    throw new Exception("Forward Header Options are missing.");
                }

                var knownProxiesSection = forwardHeadersSection.GetSection("KnownProxies").Get<string[]>();
                if (knownProxiesSection != null)
                {
                    options.KnownProxies.Clear();
                    foreach(var proxy in knownProxiesSection)
                    {
                        options.KnownProxies.Add(IPAddress.Parse(proxy));
                    }
                }
            }
            else
            {
                throw new Exception("Forward Header Section is missing.");
            }
        });

        return services;
    }

    public static void LogForwardHeaderOptionsConfiguration(this IApplicationBuilder app)
    {
        var fwdOptions = app.ApplicationServices.GetRequiredService<IOptions<ForwardedHeadersOptions>>().Value;
        Log.Information($"ForwardedHeaders config — Headers: {fwdOptions.ForwardedHeaders}, KnownProxies: {string.Join(", ", fwdOptions.KnownProxies)}");
    }
} 