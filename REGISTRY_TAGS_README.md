# GitHub Tags for Julia Registry

## Problem
The Julia General registry requires specific GitHub tags to be present in the repository. When the repository was transferred from NREL to NatLabRockies, these tags were not transferred properly. This causes the Julia registry's Treecheck CI to fail because it cannot find the registered versions.

## Solution
Tags have been created locally in this repository that point to the correct commits from the NREL repository. These tags need to be pushed to GitHub.

## Required Tags

The following 15 tags have been created and verified locally:

| Version | Tree Hash (Julia Registry) | Commit Hash | Status |
|---------|----------------------------|-------------|--------|
| v0.32.8 | `9db709e8137557d47a82143d85c0aa4e242f1661` | `77a4a120a42eda9694e2fd57cef68f9475129704` | ✓ Created |
| v0.33.0 | `acb90c48bf5a1503af0571abceba6a2308b87bb0` | `8cd9a1326b9a595b71496728ede94e2e2b0690ac` | ✓ Created |
| v0.34.0 | `2e33391bdc09b2bff01ffb099fe33c04afcc9ac4` | `1bdbb658597cc8879380b7b3f37d56d58834d2ea` | ✓ Created |
| v0.35.0 | `c7c00b10cfc323646d66a42228e0b65c96931b6d` | `8d61ed40d0bc85a604aa78965ed5dbcde1fe700a` | ✓ Created |
| v0.35.1 | `1da8a8e572060e82bb191269ecb95cb584aa7cf5` | `794c0ae95d1985b3090eff723be60867ae307321` | ✓ Created |
| v0.36.0 | `854cd4a42f88bb68979f0fa0c5bea47dc7f5de03` | `4e08fe26538b4d455f5f155a35001c7fdc896888` | ✓ Created |
| v0.37.0 | `bc9f8e83a9853e9c7f1b2be3cb83a2090ebeadcc` | `4c815c11e3c03858f954c9258d73dcaf410934ff` | ✓ Created |
| v0.37.1 | `e0f05ebbc7a7c4e8117d03f6900d93aa310e9d81` | `d84336fc81fc0e86173a93be8bf0e74b64972721` | ✓ Created |
| v0.37.2 | `09bf72fce9a954f219e3ac3129ab83221fb21ff1` | `9174cef955b1603e5c52f5bb41341f826486e195` | ✓ Created |
| v0.37.3 | `60798d610ebe263fb12bd83437309c39443c39bf` | `1f8b80213ca1080c6bf35c394c2406bd2fdd11f8` | ✓ Created |
| v0.37.4 | `6f3db36b83c7a3f8aa8d3ab187b91a5a6ac159cb` | `0085341139a2999eb14b486680832014fd5c1f3f` | ✓ Created |
| v0.37.5 | `dfdfae683357d7548a479fb37214e1f64770db10` | `8bc98f3d09e57c6a5882dbb59ca827805c3477a7` | ✓ Created |
| v0.38.0 | `919f84238b81126f41630ed1bc6daa12342c3f51` | `27eae363a470fc7f8137f1bd4e6cffb2832f9454` | ✓ Created |
| v0.38.1 | `a56f12eca2b737e9d9210000ee599920001cc303` | `e5efe256ffec6697ade71e1cdfb61212d61d5b3b` | ✓ Created |
| v0.38.2 | `373fd99edecab625cdfa492bdbeeaa4fd7b181ab` | `9fe47ebda1565c670d45e0b49cb3e68aac17eab0` | ✓ Created |

## How to Push Tags

### Option 1: Using the provided script (Recommended for local push)

If you have push access to the repository, you can run:

```bash
./push_tags.sh
```

### Option 2: Using GitHub Actions Workflow

A GitHub Actions workflow has been created at `.github/workflows/push-registry-tags.yml`. 

To use it:
1. Go to the Actions tab in GitHub
2. Select "Push Registry Tags" workflow
3. Click "Run workflow"

The workflow will:
- Fetch the required commits from the NREL repository
- Create all 15 tags
- Push them to GitHub
- Verify that each tag points to the correct tree hash

### Option 3: Manual push

```bash
# Fetch required commits from NREL
git remote add nrel https://github.com/NREL/REopt.jl
git fetch nrel 77a4a120a42eda9694e2fd57cef68f9475129704 \
             8cd9a1326b9a595b71496728ede94e2e2b0690ac \
             1bdbb658597cc8879380b7b3f37d56d58834d2ea \
             8d61ed40d0bc85a604aa78965ed5dbcde1fe700a \
             794c0ae95d1985b3090eff723be60867ae307321 \
             4e08fe26538b4d455f5f155a35001c7fdc896888 \
             4c815c11e3c03858f954c9258d73dcaf410934ff \
             d84336fc81fc0e86173a93be8bf0e74b64972721 \
             9174cef955b1603e5c52f5bb41341f826486e195 \
             1f8b80213ca1080c6bf35c394c2406bd2fdd11f8 \
             0085341139a2999eb14b486680832014fd5c1f3f \
             8bc98f3d09e57c6a5882dbb59ca827805c3477a7 \
             27eae363a470fc7f8137f1bd4e6cffb2832f9454 \
             e5efe256ffec6697ade71e1cdfb61212d61d5b3b \
             9fe47ebda1565c670d45e0b49cb3e68aac17eab0

# Create tags
git tag -a v0.32.8 77a4a120a42eda9694e2fd57cef68f9475129704 -m "Version 0.32.8"
git tag -a v0.33.0 8cd9a1326b9a595b71496728ede94e2e2b0690ac -m "Version 0.33.0"
git tag -a v0.34.0 1bdbb658597cc8879380b7b3f37d56d58834d2ea -m "Version 0.34.0"
git tag -a v0.35.0 8d61ed40d0bc85a604aa78965ed5dbcde1fe700a -m "Version 0.35.0"
git tag -a v0.35.1 794c0ae95d1985b3090eff723be60867ae307321 -m "Version 0.35.1"
git tag -a v0.36.0 4e08fe26538b4d455f5f155a35001c7fdc896888 -m "Version 0.36.0"
git tag -a v0.37.0 4c815c11e3c03858f954c9258d73dcaf410934ff -m "Version 0.37.0"
git tag -a v0.37.1 d84336fc81fc0e86173a93be8bf0e74b64972721 -m "Version 0.37.1"
git tag -a v0.37.2 9174cef955b1603e5c52f5bb41341f826486e195 -m "Version 0.37.2"
git tag -a v0.37.3 1f8b80213ca1080c6bf35c394c2406bd2fdd11f8 -m "Version 0.37.3"
git tag -a v0.37.4 0085341139a2999eb14b486680832014fd5c1f3f -m "Version 0.37.4"
git tag -a v0.37.5 8bc98f3d09e57c6a5882dbb59ca827805c3477a7 -m "Version 0.37.5"
git tag -a v0.38.0 27eae363a470fc7f8137f1bd4e6cffb2832f9454 -m "Version 0.38.0"
git tag -a v0.38.1 e5efe256ffec6697ade71e1cdfb61212d61d5b3b -m "Version 0.38.1"
git tag -a v0.38.2 9fe47ebda1565c670d45e0b49cb3e68aac17eab0 -m "Version 0.38.2"

# Push all tags
git push origin v0.32.8 v0.33.0 v0.34.0 v0.35.0 v0.35.1 v0.36.0 \
                v0.37.0 v0.37.1 v0.37.2 v0.37.3 v0.37.4 v0.37.5 \
                v0.38.0 v0.38.1 v0.38.2
```

## Verification

After pushing, you can verify the tags at:
https://github.com/NatLabRockies/REopt.jl/tags

You can also verify that each tag points to the correct tree hash:

```bash
git log -1 --format="%T" v0.32.8  # Should output: 9db709e8137557d47a82143d85c0aa4e242f1661
# ... repeat for other tags
```

## Next Steps

Once the tags are pushed to GitHub:
1. The Julia registry's Treecheck CI should pass
2. The registry PR at https://github.com/JuliaRegistries/General/pull/148202 can be merged
3. The REopt.jl package URL will be successfully updated from NREL to NatLabRockies

## Background

The tree hashes in the Julia registry represent the state of the repository at the time each version was registered. When versions are registered with Julia's Registrator, it records the git tree hash (not the commit hash) for that version. The Treecheck CI verifies that each registered version can be found in the repository by checking that a tag exists pointing to a commit with the matching tree hash.

During the repository transfer from NREL to NatLabRockies, the tags either weren't transferred or were pointing to different commits. This PR recovers the original commits from the NREL repository and creates the proper tags.
