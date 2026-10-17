import jenkins.model.Jenkins
import jenkins.model.JenkinsLocationConfiguration
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy

def jenkins = Jenkins.get()

def loc = JenkinsLocationConfiguration.get()
if (loc.getUrl() == null || loc.getUrl().isEmpty()) {
    loc.setUrl("http://localhost:8080/")
    loc.save()
    println "[init] Jenkins URL set"
}

def realm = jenkins.getSecurityRealm()
if (!(realm instanceof HudsonPrivateSecurityRealm)) {
    realm = new HudsonPrivateSecurityRealm(false, false, null)
    jenkins.setSecurityRealm(realm)
    println "[init] security realm created"
}

def existing = realm.getAllUsers().collect { it.id }
if (!existing.contains("admin")) {
    realm.createAccount("admin", "admin123")
    println "[init] created admin user (existing users: ${existing})"
} else {
    println "[init] admin user already exists"
}

if (jenkins.getAuthorizationStrategy() == null ||
    jenkins.getAuthorizationStrategy() instanceof hudson.security.AuthorizationStrategy$Unsecured) {
    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    strategy.setAllowAnonymousRead(false)
    jenkins.setAuthorizationStrategy(strategy)
    println "[init] authorization strategy set"
}

jenkins.save()
println "[init] basic config done"
