**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

Maintenance Policy for RAAF
===========================

Support of the RAAF framework is divided into three groups: New features, bug fixes, and security issues. They are handled as follows, all versions, except for security releases, in X.Y.Z, format.

After reading this guide, you will know:

* How RAAF releases are versioned.
* What to expect from RAAF releases.
* Which versions of RAAF are currently supported.
* When to expect new RAAF releases.

--------------------------------------------------------------------------------

Versioning
----------

RAAF follows [Semantic Versioning](https://semver.org/) for all releases:

* **Major versions** (X.0.0) - Contain breaking changes, new features, and bug fixes
* **Minor versions** (X.Y.0) - Contain new features and bug fixes, but no breaking changes
* **Patch versions** (X.Y.Z) - Contain only bug fixes and security patches

### Major Version Support

RAAF maintains **two major versions** simultaneously:

* **Current major version** - Receives new features, bug fixes, and security updates
* **Previous major version** - Receives bug fixes and security updates only

### Minor Version Support

Within each major version, RAAF supports:

* **Current minor version** - Receives new features, bug fixes, and security updates
* **Previous minor version** - Receives bug fixes and security updates only

### Patch Version Support

Only the **latest patch version** within each supported minor version receives updates.

Supported Versions
------------------

As of today, the following versions are supported:

| Version | Bug Fixes | Security Issues |
| ------- | --------- | --------------- |
| 2.1.x   | Yes       | Yes             |
| 2.0.x   | Yes       | Yes             |
| 1.2.x   | Yes       | Yes             |
| 1.1.x   | No        | Yes             |
| 1.0.x   | No        | Yes             |

### End of Life

When a RAAF version reaches end of life, it will no longer receive:

* Security patches
* Bug fixes
* New features

We recommend upgrading to a supported version as soon as possible.

Release Schedule
----------------

RAAF aims to release:

* **Major versions**: Every 12-18 months
* **Minor versions**: Every 3-4 months
* **Patch versions**: As needed for critical bug fixes and security issues

NOTE: This schedule may vary based on development priorities and community needs.

### Pre-release Versions

RAAF provides pre-release versions for testing:

* **Alpha releases** - Early development versions with new features
* **Beta releases** - Feature-complete versions for testing
* **Release candidates** - Near-final versions for final testing

Unsupported Versions
--------------------

The following versions are no longer supported:

* **RAAF 0.x.x** - All versions (End of life)

These versions will not receive security patches or bug fixes.

Severe Security Issues
----------------------

For severe security issues, RAAF may provide patches for additional versions beyond the normal support policy. These patches will be released as emergency security updates.

Reporting Security Issues
-------------------------

Please report security issues to our [security team](https://github.com/raaf-ai/raaf/security/advisories/new) rather than the public issue tracker.

We take security seriously and will:

* Acknowledge receipt within 24 hours
* Provide regular updates on progress
* Credit reporters (unless they prefer to remain anonymous)
* Coordinate disclosure timing

Long Term Support (LTS)
-----------------------

RAAF is considering implementing Long Term Support (LTS) versions for enterprise users. LTS versions would receive:

* Extended security support (3+ years)
* Critical bug fixes
* Backported stability improvements

This is under consideration and will be announced if implemented.

Upgrade Path
------------

RAAF provides comprehensive upgrade guides for:

* **Major version upgrades** - Detailed migration guides with breaking changes
* **Minor version upgrades** - Feature additions and deprecation notices
* **Patch version upgrades** - Critical fixes and security patches

See our [Migration Guide](migration_guide.html) for detailed upgrade instructions.

Community Support
-----------------

Beyond official support, the RAAF community provides:

* **GitHub Discussions** - Community help and questions
* **Community Plugins** - Third-party extensions and tools
* **Community Contributions** - Bug reports, feature requests, and pull requests

The community often provides unofficial support for older versions through:

* Community-maintained patches
* Third-party security backports
* Migration assistance

NOTE: Community support is not guaranteed and may vary in quality and availability.

Enterprise Support
------------------

For enterprise users requiring extended support, commercial support options may be available. Contact [Enterprise Modules B.V.](mailto:support@enterprisemodules.com) for:

* Extended version support
* Priority bug fixes
* Custom feature development
* Training and consulting services

Deprecation Policy
------------------

RAAF follows a clear deprecation policy:

1. **Announcement** - Features are marked as deprecated with clear migration paths
2. **Warning Period** - Deprecated features issue warnings but remain functional
3. **Removal** - Deprecated features are removed in the next major version

### Deprecation Timeline

* **Minor version** - Features may be deprecated
* **Major version** - Deprecated features are removed
* **Security issues** - May bypass normal deprecation for immediate removal

Beta and Experimental Features
-------------------------------

RAAF may include beta and experimental features:

* **Beta features** - Stable but may have breaking changes
* **Experimental features** - May change significantly or be removed

These features are clearly marked in documentation and may not follow the normal support policy.

Getting Help
------------

For help with RAAF versions and support:

* **Documentation** - Check the [official guides](https://guides.raaf.dev)
* **GitHub Issues** - Report bugs and request features
* **GitHub Discussions** - Ask questions and get community help
* **Security Issues** - Use the security reporting process

The RAAF core team monitors these channels and provides support within the maintenance policy guidelines.