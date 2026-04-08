# MeedyaSuite-core Integration Plan

## Overview

MeedyaConverter will integrate with MeedyaSuite-core to share metadata provider
infrastructure with MeedyaDL and MeedyaManager. Since MeedyaConverter is a Swift
project, integration requires the Swift bindings layer from MeedyaSuite-core.

## Integration Path

### Phase 1: Swift Bindings (MeedyaSuite-core)
MeedyaSuite-core needs to build its `bindings/swift/` package, exposing:
- `MetadataProvider` trait as a Swift protocol via C FFI
- `ProviderRegistry` for multi-provider search
- `CredentialStore` for unified credential management
- Codec detection via `meedya-codecs`

### Phase 2: Package.swift Dependency
Once Swift bindings are available:
```swift
.package(url: "https://github.com/MWBMPartners/MeedyaSuite-core", branch: "main")
```

### Phase 3: Provider Migration
Replace in MeedyaConverter:
- `MetadataLookup.swift` (MetadataSource enum) -> use meedya-core providers
- `MetadataProviders.swift` (TheTVDB client) -> use meedya-core TheTVDB provider
- Remove inline API clients for TMDB, MusicBrainz, Discogs, etc.

### Phase 4: Codec Integration
Use meedya-core codec types in:
- `CodecMetadataPreserver.swift`
- `MetadataPassthrough.swift`
- `StreamMetadataEditor.swift`

## Files to Modify

| File | Action |
|------|--------|
| `Package.swift` | Add meedya-core Swift package dependency |
| `Sources/ConverterEngine/Metadata/MetadataLookup.swift` | Replace with meedya-core providers |
| `Sources/ConverterEngine/Metadata/MetadataProviders.swift` | Remove (handled by meedya-core) |
| `Sources/ConverterEngine/FFmpeg/CodecMetadataPreserver.swift` | Use shared codec types |

## Status

- [x] GitHub issues created
- [x] Integration branch created
- [ ] Swift bindings built in MeedyaSuite-core
- [ ] Package.swift dependency added
- [ ] Provider migration
- [ ] Codec integration
- [ ] Remove redundant code
