pipeline {
    agent any
    options {
        timestamps()
        timeout(time: 180, unit: 'MINUTES')
        skipDefaultCheckout(true)
    }
    environment {
        REPO_URL = 'https://github.com/ProjectViVy/agent-vivy.git'
    }
    stages {
        stage('Checkout') {
            steps {
                echo 'Linux port of .github/workflows/ci.yml (backend lane + ui lane). Windows-only steps are skipped: see stage names with [skip].'
                checkout([$class: 'GitSCM',
                    branches: [[name: '*/main']],
                    doGenerateSubmoduleConfigurations: false,
                    extensions: [[$class: 'WipeWorkspace']],
                    submoduleCfg: [],
                    userRemoteConfigs: [[url: env.REPO_URL]]])
                sh 'git log --oneline -1 && git status --porcelain | head -5'
            }
        }
        stage('PrepareLaputa (ensure-laputa.ps1)') {
            steps {
                sh '''
                    pwsh -NoProfile -File ./scripts/ensure-laputa.ps1 -Quiet
                    git -C ../laputa log --oneline -1
                '''
            }
        }
        stage('BootstrapTest') {
            steps {
                sh 'node --test scripts/ensure-laputa.test.mjs scripts/dependency-closure.test.mjs'
            }
        }
        stage('FmtCheck') {
            steps {
                sh '''
                    files=$(git ls-files --cached --others --exclude-standard -- '*.go')
                    count=$(printf '%s\n' "$files" | grep -c . || true)
                    unformatted=$(printf '%s\n' "$files" | xargs -r gofmt -l)
                    if [ -n "$unformatted" ]; then
                        echo "$unformatted"
                        exit 1
                    fi
                    echo "gofmt clean: $count files"
                '''
            }
        }
        stage('UiBuild') {
            steps {
                sh '''
                    cd ui
                    pnpm install --frozen-lockfile
                    pnpm build
                '''
            }
        }
        stage('GoVet') {
            steps {
                sh 'go vet ./...'
            }
        }
        stage('GoTest') {
            steps {
                sh '''go test -p 1 -timeout 35m -skip '^TestMemoryLoop' ./...'''
            }
        }
        stage('HeadlessCompile') {
            steps {
                sh '''go test -run '^$' -tags vivy_headless ./cmd/vivy ./cmd/vivy-code ./ui'''
            }
        }
        stage('PluginCI') {
            steps {
                sh '''
                    find plugins faces -name go.mod -type f 2>/dev/null | sort > /tmp/plugin-mods.txt
                    fail=0
                    while IFS= read -r mod; do
                        d=$(dirname "$mod")
                        echo "== plugin-ci: $d"
                        ( cd "$d" && go vet ./... ) || fail=1
                        ( cd "$d" && go test ./... ) || fail=1
                    done < /tmp/plugin-mods.txt
                    exit $fail
                '''
            }
        }
        stage('UiCore (typecheck+test)') {
            steps {
                sh '''
                    cd ui
                    pnpm typecheck
                    pnpm test
                '''
            }
        }
        stage('I18nCheck') {
            steps {
                sh '''
                    node scripts/check-i18n-completeness.js
                    node --test scripts/check-i18n-cross-face.test.js
                    node scripts/check-i18n-cross-face.js
                '''
            }
        }
    }
    post {
        success {
            echo 'vivy CI (Linux port) PASSED'
        }
        failure {
            echo 'vivy CI (Linux port) FAILED - see stage logs'
        }
        always {
            echo "Result: ${currentBuild.currentResult} (${currentBuild.durationString})"
        }
    }
}
