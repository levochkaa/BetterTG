#!/usr/bin/env bash
set -euo pipefail

LOG_PATH="${1:-xcodebuild log}"

awk -v log_path="$LOG_PATH" '
  function shortened(line) {
    if (length(line) > 240) {
      return substr(line, 1, 237) "..."
    }
    return line
  }

  BEGIN {
    progress = 0
    suppressed = 0
    swiftformat_warnings = 0
    other = 0
    max_other = 20
  }

  /^$/ {
    next
  }

  /warning: \([[:alnum:]_]+\)/ {
    swiftformat_warnings += 1
    suppressed += 1
    next
  }

  /warning: Metadata extraction (disabled|skipped)/ {
    suppressed += 1
    next
  }

  /(^\*\* (BUILD|ARCHIVE) (FAILED|SUCCEEDED) \*\*$|[Ee]rror:|fatal error:|Command .* failed|No such file|Undefined symbols)/ {
    print
    next
  }

  /^(Resolve Package Graph|Resolved source packages|Fetching |Creating working copy|Checking out |Cloning |note: Building targets|note: Target dependency graph)/ {
    print
    next
  }

  /^(Compile|SwiftCompile|SwiftDriver|Ld |ProcessInfoPlistFile|CodeSign|PhaseScriptExecution|Copy |CpResource|Touch |CreateBuildDirectory|MkDir |WriteAuxiliaryFile|GenerateDSYMFile|CompileAssetCatalog|ProcessProductPackaging|Validate|RegisterExecutionPolicyException)/ {
    progress += 1
    if (progress == 1 || progress % 100 == 0) {
      print "[xcodebuild] progress " progress ": " shortened($0)
    } else {
      suppressed += 1
    }
    next
  }

  /[Ww]arning:/ {
    print
    next
  }

  {
    other += 1
    if (other <= max_other) {
      print
    } else {
      suppressed += 1
    }
  }

  END {
    if (swiftformat_warnings > 0) {
      print "[SwiftFormat] " swiftformat_warnings " lint warnings; full details: " log_path
    }
    if (suppressed > 0) {
      print "[xcodebuild] suppressed " suppressed " verbose lines; full log: " log_path
    }
  }
'
