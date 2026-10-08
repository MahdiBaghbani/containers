#!/usr/bin/env nu
use std/assert
use ../../../scripts/lib/manifest/core.nu [apply-version-defaults]

def merged [root: string, service: string, version: string] {
    let manifest = (open ($root | path join "services" $service "versions.nuon"))
    let selected = ($manifest.versions | where name == $version | first)
    apply-version-defaults $manifest $selected
}

def main [] {
    let root = ($env.FILE_PWD | path dirname | path dirname | path dirname)
    let app = (merged $root "nextcloud-webapp" "webapp-share")
    assert equal $app.overrides.sources.integration_jupyterhub.url "https://github.com/SUNET/nextcloud-integration_jupyterhub"
    assert equal $app.overrides.sources.integration_jupyterhub.ref "main"
    assert equal $app.overrides.sources.ocmremotewebapp.ref "main"
    assert equal $app.overrides.dependencies.nextcloud-contacts.version "ocm-webapp-share-debian"
    for version in ["ocm-webapp-share"] {
        let contacts = (merged $root "nextcloud-contacts" $version)
        assert equal $contacts.overrides.sources.contacts.url "https://github.com/sara-nl/nextcloud-contacts"
        assert equal $contacts.overrides.sources.contacts.ref "fix-undefined-group-ocm-invites-routes"
        assert equal $contacts.overrides.dependencies.nextcloud.version "v35.0.1-debian"
        assert equal $contacts.latest false
    }
    let hub = (merged $root "jupyterhub" "webapp-share")
    assert equal $hub.overrides.sources.integration_jupyterhub.url $app.overrides.sources.integration_jupyterhub.url
    assert equal $hub.overrides.sources.integration_jupyterhub.ref $app.overrides.sources.integration_jupyterhub.ref
    assert equal $hub.overrides.external_images.runtime.tag "5.3.0"
    print "PASS: 11 webapp source and dependency assertions"
}
