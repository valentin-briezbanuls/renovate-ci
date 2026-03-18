($trivy[0].Results // $trivy[0].results // []) as $trivyResults |
($trivyResults | map((.Vulnerabilities // .vulnerabilities // [])) | flatten) as $trivyVulns |
($osv[0].results // []) as $osvResults |
($osvResults | map(.packages // []) | flatten) as $osvPackages |
(($spm_resolved[0].pins // []) | map({(.identity): .location}) | add // {}) as $spm_urls |
{
  "report": {
    "generated_at": $timestamp,
    "pipeline_id": $pipeline_id,
    "commit_sha": $commit_sha,
    "branch": $branch,
    "platform": $platform,
    "target_repo": $target_repo,
    "format_version": "1.0"
  },
  "security": {
    "osv_scanner": $osv[0],
    "trivy_scanner": $trivy[0],
    "summary": {
      "total_packages_with_vulnerabilities": (
        (
          [ $osvPackages[]? | select((.vulnerabilities | length) > 0) | .package.name ] +
          [ $trivyVulns[]? | .PkgName ]
        ) | map(select(. != null and . != "")) | unique | length
      ),
      "total_vulnerabilities": (
        ([$osvPackages[]?.vulnerabilities[]?] | length) +
        ($trivyVulns | length)
      ),
      "osv_total_vulnerabilities": ([$osvPackages[]?.vulnerabilities[]?] | length),
      "trivy_total_vulnerabilities": ($trivyVulns | length),
      "osv_vulnerable_packages": (
        [
          $osvPackages[]?
          | select((.vulnerabilities | length) > 0)
          | {
              name: .package.name,
              version: .package.version,
              ecosystem: .package.ecosystem,
              vulnerability_count: (.vulnerabilities | length),
              vulnerabilities: [
                .vulnerabilities[]
                | {
                    id: .id,
                    summary: .summary,
                    severity: (.database_specific.severity // "UNKNOWN"),
                    cvss_vector: (.severity[0].score // null),
                    cvss_type: (.severity[0].type // null),
                    aliases: .aliases,
                    published: .published,
                    modified: .modified,
                    references: .references
                  }
              ]
            }
        ]
      ),
      "trivy_vulnerable_packages": (
        [
          $trivyVulns[]?
          | {
              name: .PkgName,
              version: .InstalledVersion,
              fixed_version: .FixedVersion,
              ecosystem: .PkgType,
              vulnerability_id: .VulnerabilityID,
              severity: .Severity,
              title: (.Title // .Description // .PrimaryURL // "")
            }
        ]
      ),
      "cves": (
        (
          [$osvPackages[]?.vulnerabilities[]?.aliases[]? | select(test("^CVE-"))] +
          [$trivyVulns[]?.VulnerabilityID | select(. != null and test("^CVE-"))]
        ) | unique
      ),
      "severity_levels": (
        (
          [$osvPackages[]?.vulnerabilities[]?.database_specific?.severity? | select(. != null)] +
          [$trivyVulns[]?.Severity | select(. != null)]
        ) | unique
      ),
      "all_ios_packages": (
        (
          $trivyResults
          | map(
              . as $result |
              ($result.Packages // [])
              | map({
                  name: .Name,
                  version: (.Version // ""),
                  package_manager: ($result.Type | ascii_downcase)
                })
            )
          | flatten
          | map(select(.package_manager == "swift" or .package_manager == "cocoapods"))
          | unique_by(.name)
        ) as $ios_packages
        |
        (
          ($spm_resolved[0].pins // [])
          | map({
              key_identity: (.identity // "" | ascii_downcase),
              key_repo: ((.location // "" | split("/") | last | sub("\\.git$"; "") | ascii_downcase)),
              location: .location
            })
        ) as $spm_entries
        |
        ($spm_entries | map({(.key_identity): .location}) | add // {}) as $spm_by_identity
        |
        ($spm_entries | map({(.key_repo): .location}) | add // {}) as $spm_by_repo
        |
        $ios_packages
        | map(
            . as $pkg
            | ($pkg.name | ascii_downcase) as $name_lower
            | ($name_lower | gsub("[^a-z0-9]"; "")) as $name_norm
            | . + {
                source_url: (
                  $spm_by_identity[$name_lower]
                  // $spm_by_repo[$name_lower]
                  // ([ $spm_entries[]? | select((.key_identity | gsub("[^a-z0-9]"; "")) == $name_norm) | .location ][0])
                  // ([ $spm_entries[]? | select((.key_repo | gsub("[^a-z0-9]"; "")) == $name_norm) | .location ][0])
                  // ([ $spm_entries[]?
                        | select(
                            (.key_identity | gsub("[^a-z0-9]"; "")) as $id_norm
                            | ($id_norm | startswith($name_norm)) or ($name_norm | startswith($id_norm))
                          )
                        | .location
                     ][0])
                  // ([ $spm_entries[]?
                        | select(
                            (.key_repo | gsub("[^a-z0-9]"; "")) as $repo_norm
                            | ($repo_norm | startswith($name_norm)) or ($name_norm | startswith($repo_norm))
                          )
                        | .location
                     ][0])
                  // null
                )
              }
          )
      )
    }
  },
  "dependencies": {
    "renovate": $renovate[0],
    "summary": {
      "total_updates_available": ($renovate[0].updates // [] | length),
      "security_updates": ([$renovate[0].updates[]? | select(.hasVulnerabilityAlert == true)] | length),
      "update_types": ([$renovate[0].updates[]?.updateType // empty] | group_by(.) | map({type: .[0], count: length}))
    }
  },
  "recommendations": {
    "priority_actions": (
      if (([$osvPackages[]?.vulnerabilities[]?] | length) + ($trivyVulns | length)) > 0 then
        ["Review security vulnerabilities immediately", "Apply security patches first", "Update vulnerable packages"]
      else
        ["No security issues detected", "Review available dependency updates", "Continue regular maintenance"]
      end
    ),
    "vulnerable_packages_for_renovate": (
      (
        [$osvPackages[]? | select((.vulnerabilities | length) > 0) | .package.name] +
        [$trivyVulns[]? | .PkgName]
      ) | map(select(. != null and . != "")) | unique
    )
  },
  "performance": ($perf[0] // []),
  "performance_osv": ($osv_perf[0] // []),
  "performance_trivy": ($trivy_perf[0] // [])
}
