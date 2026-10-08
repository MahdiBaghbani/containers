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
    let server = (merged $root "nextcloud" "ocm-webapp-share")
    assert equal $server.overrides.sources.nextcloud.url "https://github.com/nextcloud/server"
    assert equal $server.overrides.sources.nextcloud.ref "505ceff9fa66cc67c78d41eb79fbd70ba79b61f6"
    assert equal $server.latest false
    assert equal $server.overrides.dependencies.nextcloud-base.version "8.3-apache-debian"
    let app = (merged $root "nextcloud-webapp" "webapp-share")
    assert equal $app.overrides.sources.integration_jupyterhub.url "https://github.com/SUNET/nextcloud-integration_jupyterhub"
    assert equal $app.overrides.sources.integration_jupyterhub.ref "main"
    assert equal $app.overrides.sources.ocmremotewebapp.ref "50e99b14c937c850367401ee7d593e1b1d78f17c"
    assert equal $app.overrides.dependencies.nextcloud-contacts.version "ocm-webapp-share-debian"
    for version in ["ocm-contacts-app", "ocm-webapp-share"] {
        let contacts = (merged $root "nextcloud-contacts" $version)
        assert equal $contacts.overrides.sources.contacts.url "https://github.com/sara-nl/nextcloud-contacts"
        assert equal $contacts.overrides.sources.contacts.ref "286de13e5eb6bcbb2cb18931948fe86a3f0f8187"
        assert equal $contacts.overrides.dependencies.nextcloud.version $"($version)-debian"
        assert equal $contacts.latest false
    }
    let hub = (merged $root "jupyterhub" "webapp-share")
    assert equal $hub.overrides.sources.integration_jupyterhub.url $app.overrides.sources.integration_jupyterhub.url
    assert equal $hub.overrides.sources.integration_jupyterhub.ref $app.overrides.sources.integration_jupyterhub.ref
    assert equal $hub.overrides.external_images.runtime.tag "5.3.0"
    print "PASS: 19 webapp source and dependency assertions"
}
