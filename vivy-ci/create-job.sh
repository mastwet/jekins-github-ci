#!/bin/bash
# 用 pipeline.groovy 的内容创建/更新 Jenkins job "vivy-ci"
set -euo pipefail
cd "$(dirname "$0")"

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_AUTH="${JENKINS_AUTH:-admin:admin123}"

/usr/bin/python3 - << 'PYEOF' > /tmp/vivy-ci-job.xml
script = open('pipeline.groovy', encoding='utf-8').read()
assert ']]>' not in script, 'pipeline script must not contain ]]>'
xml = f"""<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Linux port of agent-vivy .github/workflows/ci.yml (backend + ui lanes; Windows-only steps skipped)</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script><![CDATA[{script}]]></script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
"""
print(xml, end='')
PYEOF

JAR=/tmp/vivy-ci-cookies.txt
crumb=$(curl -s -c "$JAR" -u "$JENKINS_AUTH" "$JENKINS_URL/crumbIssuer/api/json" | sed -E 's/.*"crumb":"([^"]+)".*/\1/')

exist_code=$(curl -s -o /dev/null -w "%{http_code}" -u "$JENKINS_AUTH" "$JENKINS_URL/job/vivy-ci/api/json")
if [ "$exist_code" = "200" ]; then
  url="$JENKINS_URL/job/vivy-ci/config.xml"; verb="updated"
else
  url="$JENKINS_URL/createItem?name=vivy-ci"; verb="created"
fi

code=$(curl -s -o /dev/null -w "%{http_code}" -u "$JENKINS_AUTH" -b "$JAR" \
  -H "Jenkins-Crumb: $crumb" -H "Content-Type: application/xml" \
  --data-binary @/tmp/vivy-ci-job.xml "$url")
echo "job $verb: HTTP $code"
