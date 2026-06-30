import argparse
import plistlib
import os
import re

DNS_SD_PATH: str = "/usr/bin/dns-sd"
IP_V4_REGEX_PATTERN: re.Pattern = re.compile(r"^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$")

class DNSSDLaunchDaemonConfig:

    def __init__(self, label: str, service_name: str, application_layer: str, transmission_layer: str, domain: str, port: int, hostname: str, log_dir: str, address: str, run_at_load: bool, keep_alive: bool) -> None:
        self.label = label
        self.service_name = service_name
        self.application_layer = application_layer
        self.transmission_layer = transmission_layer
        self.domain = domain
        self.port = int(port)
        self.hostname = hostname
        self.log_dir = log_dir
        self.address = address
        self.run_at_load = bool(run_at_load)
        self.keep_alive = bool(keep_alive)

    def to_dict(self) -> dict:
        return {
            "Label": self.label.lower(),
            "ProgramArguments": [
                DNS_SD_PATH,
                "-P",
                self.service_name.lower(),
                f"_{self.application_layer.lower()}._{self.transmission_layer.lower()}",
                self.domain.lower(),
                str(self.port),
                self.hostname.lower(),
                self.address
            ],
            "RunAtLoad": self.run_at_load,
            "KeepAlive": self.keep_alive,
            "StandardOutPath": str(self.log_dir + f"/{self.label.lower().replace('.', '-')}.log"),
            "StandardErrorPath": str(self.log_dir + f"/{self.label.lower().replace('.', '-')}-error.log")
        }
    
    def __str__(self) -> str:
        return plistlib.dumps(self.to_dict()).decode()
    
class ValidateLogDir(argparse.Action):
    def __call__(self, parser, namespace, values, option_string=None):
        if not os.path.isdir(str(values)):
            raise argparse.ArgumentError(self, f"{values} does not exist.")
        setattr(namespace, self.dest, values)

class ValidateIPv4(argparse.Action):
    def __call__(self, parser, namespace, values, option_string=None):
        if not re.fullmatch(IP_V4_REGEX_PATTERN, str(values)):
            raise argparse.ArgumentError(self, f"{values} needs to follow IPv4 format.")
        setattr(namespace, self.dest, values)
    
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a launchd plist for a dns-sd service registration")
    
    parser.add_argument("-l", "--label", required=True, help="launchd Label, e.g. com.healthcrm.local.mdns")
    parser.add_argument("-n", "--service-name", required=True, help="DNS-SD Service name, e.g. HealthCRM")
    parser.add_argument("-a", "--application-layer", required=True, help="e.g. http or https")
    parser.add_argument("-t", "--transmission-layer", required=True, help="e.g. tcp or udp")
    parser.add_argument("-d", "--domain", required=True, help="e.g. local")
    parser.add_argument("-p", "--port", required=True, help="e.g. 443")
    parser.add_argument("-o", "--hostname", required=True, help="e.g. healthcrm.local")
    parser.add_argument("-g", "--log-dir", action=ValidateLogDir, required=True, help="Directory for stdout/stderr log files")
    parser.add_argument("-i", "--address", default="127.0.0.1", action=ValidateIPv4, help="IP Address (default: 127.0.0.1)")
    parser.add_argument("--run-at-load", default=True, action=argparse.BooleanOptionalAction, help="Whether launchd should run the daemon at load time (default: True)")
    parser.add_argument("--keep-alive", default=True, action=argparse.BooleanOptionalAction, help="Whether launchd should keep the daemon alive / restart it (default: True)")

    return parser.parse_args()
    
if __name__ == "__main__":
    args = parse_args()

    dnsSd = DNSSDLaunchDaemonConfig(
        label=args.label,
        service_name=args.service_name,
        application_layer=args.application_layer,
        transmission_layer=args.transmission_layer,
        domain=args.domain,
        port=args.port,
        hostname=args.hostname,
        log_dir=args.log_dir,
        address=args.address,
        run_at_load=args.run_at_load,
        keep_alive=args.keep_alive
    )

    print(dnsSd)