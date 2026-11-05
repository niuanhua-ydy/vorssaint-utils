#!/bin/bash
# Focused production-code tests; independent of unrelated generated app fixtures.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d "${TMPDIR:-/tmp}/vorssaint-command-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
python3 - "$WORK" <<'PY'
from pathlib import Path
import sys
out = Path(sys.argv[1])
suite = Path('Tests/TestSuite.swift').read_text().split('enum TestHarnessTests {')[0]
(out / 'TestSuite.swift').write_text(suite)
# Compile the actual legacy PID parser too, with only its localized labels stubbed.
# Like Tests/generate_sources.py, fail closed if declarations change shape.
source = Path('Sources/Vorssaint/Services/KillProcess/KillProcessSupport.swift').read_text().splitlines(keepends=True)
def declaration(prefix):
    starts = [i for i, line in enumerate(source) if line.startswith(prefix)]
    assert len(starts) == 1, prefix
    start = starts[0]
    end = next(i for i in range(start + 1, len(source)) if source[i].rstrip() == '    }')
    return ''.join(source[start:end + 1])
fixture = """import Foundation
enum AppLanguage { case enUS, zhHans }
enum FeatureStrings {
    struct Labels { let forceKillButton: String; let killButton: String; let pageTitle: String }
    static func killProcess(_ language: AppLanguage) -> Labels {
        language == .enUS ? Labels(forceKillButton: "Force Kill", killButton: "Kill", pageTitle: "Kill Process")
                         : Labels(forceKillButton: "强制结束", killButton: "结束", pageTitle: "结束进程")
    }
}
enum MetricFormat { static func includeNetworkInterface(_ name: String) -> Bool { name.hasPrefix("en") } }
enum KillProcessSupport {
"""
for prefix in ['    static func pidQuery(', '    static func isForceKillQuery(',
               '    private static func isValidPIDDigits(', '    private static func parsePIDQuery(']:
    fixture += declaration(prefix)
fixture += ''.join(line for line in source if line.startswith('    private static let forceSignalFlags:')
                   or line.startswith('    private static let gracefulSignalFlags:')) + '}\n'
(out / 'LegacyPID.swift').write_text(fixture)
(out / 'Main.swift').write_text('''import Foundation
@main struct Main {
    @MainActor static func main() async {
        let suite = TestSuite()
        suite.run("system-commands") { CommandBarSystemTests.run(suite) }
        await CommandBarSystemTests.runAsync(suite)
        for query in ["kill :3000", "kill -9 :3000", ":3000", "kill :0", "kill :65536"] {
            suite.expect(KillProcessSupport.pidQuery(from: query, allowBareDigits: true, language: .enUS) == nil,
                         "legacy PID parser must never interpret a port as a PID: " + query)
        }
        for query in ["pid:4242", "pid=4242", "kill 4242", "kill -9 4242", "kill -KILL 4242"] {
            suite.expect(KillProcessSupport.pidQuery(from: query, allowBareDigits: false, language: .enUS) == "4242",
                         "legacy PID syntax preserved: " + query)
        }
        let addresses = NetworkAddressService.commandBarAddresses()
        suite.expect(addresses.allSatisfy { CommandBarIPQuery.usableLocal($0.address) && !$0.interface.isEmpty && !$0.name.isEmpty },
                     "real system interface snapshot contains only usable, labeled IPv4 addresses")
        suite.expect(Set(addresses.map { $0.interface + "|" + $0.address }).count == addresses.count,
                     "real interface snapshot is unique by interface/address")
        suite.expect(addresses.firstIndex(where: { !$0.isPrimary }) == nil
                        || !addresses.drop(while: { $0.isPrimary }).contains(where: { $0.isPrimary }),
                     "primary interfaces precede other interfaces")
        suite.finish()
    }
}
''')
PY
swiftc -swift-version 5 -module-cache-path "$WORK/module-cache" \
    Sources/Vorssaint/Services/CommandBar/CommandBarSystemSupport.swift \
    Sources/Vorssaint/Services/CommandBar/CommandBarInstantAnswers.swift \
    Sources/Vorssaint/Services/Metrics/NetworkAddressService.swift \
    Tests/CommandBarSystemTests.swift "$WORK/TestSuite.swift" "$WORK/LegacyPID.swift" "$WORK/Main.swift" \
    -o "$WORK/tests"
"$WORK/tests"
