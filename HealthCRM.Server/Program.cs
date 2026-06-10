using HealthCRM.Server.Extensions;
using Microsoft.AspNetCore.HttpLogging;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .CreateBootstrapLogger();

try
{

    builder.WebHost.ConfigureKestrelHttpsDefaults(builder.Configuration, builder.Environment);

    builder.Services.AddSerilog((services, lc) => lc
        .ReadFrom.Configuration(builder.Configuration)
        .ReadFrom.Services(services)
        .Enrich.FromLogContext()
    );
    
    if (builder.Environment.IsDevelopment() || builder.Environment.IsStaging())
    {
        builder.Services.AddHttpLogging(o => { 
            o.LoggingFields = HttpLoggingFields.All; 
            o.RequestHeaders.Add("Referer");
            o.RequestHeaders.Add("sec-ch-ua-platform");
            o.RequestHeaders.Add("sec-ch-ua");
            o.RequestHeaders.Add("sec-ch-ua-mobile");
            o.RequestHeaders.Add("sec-fetch-site");
            o.RequestHeaders.Add("sec-fetch-mode");
            o.RequestHeaders.Add("sec-fetch-dest");
            o.RequestHeaders.Add("priority");
            o.RequestHeaders.Add("X-Forwarded-For");
            o.RequestHeaders.Add("X-Forwarded-Proto");
            o.RequestHeaders.Add("X-Original-For");
            o.RequestHeaders.Add("X-Original-Proto");
        });

        builder.Services.AddOpenApi();
    }

    builder.Services.AddForwardHeaderOptionsConfiguration(builder.Configuration, builder.Environment);
    
    builder.Services.AddControllers();
    
    var app = builder.Build();
    
    app.UseForwardedHeaders();
    app.UseSerilogRequestLogging();
    
    Log.Information("Application started! Logging to both console and/or file.");
    
    app.LogForwardHeaderOptionsConfiguration();

    if (app.Environment.IsDevelopment() || app.Environment.IsStaging())
    {
        app.UseHttpLogging();
        app.MapOpenApi();
    }

    app.UseHttpsRedirection();
    app.UseAuthorization();
    app.MapControllers();
    app.Run();

}
catch (Exception ex)
{
    Log.Fatal(ex, "Application start-up failed!");
}
finally
{
    Log.CloseAndFlush();
}