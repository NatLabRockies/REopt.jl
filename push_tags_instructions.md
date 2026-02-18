# Instructions to Push Tags for Julia Registry

The following 15 tags have been created locally and need to be pushed to GitHub:

- v0.32.8
- v0.33.0
- v0.34.0
- v0.35.0
- v0.35.1
- v0.36.0
- v0.37.0
- v0.37.1
- v0.37.2
- v0.37.3
- v0.37.4
- v0.37.5
- v0.38.0
- v0.38.1
- v0.38.2

## To push these tags, run:

```bash
git push origin v0.32.8 v0.33.0 v0.34.0 v0.35.0 v0.35.1 v0.36.0 v0.37.0 v0.37.1 v0.37.2 v0.37.3 v0.37.4 v0.37.5 v0.38.0 v0.38.1 v0.38.2
```

Or push all tags at once:

```bash
git push origin --tags
```

## Verification

Each tag points to a commit whose tree hash matches the Julia registry requirements:

| Version | Tree Hash (from Julia Registry) | Commit Hash |
|---------|--------------------------------|-------------|
| v0.32.8 | 9db709e8137557d47a82143d85c0aa4e242f1661 | 77a4a120a42eda9694e2fd57cef68f9475129704 |
| v0.33.0 | acb90c48bf5a1503af0571abceba6a2308b87bb0 | 8cd9a1326b9a595b71496728ede94e2e2b0690ac |
| v0.34.0 | 2e33391bdc09b2bff01ffb099fe33c04afcc9ac4 | 1bdbb658597cc8879380b7b3f37d56d58834d2ea |
| v0.35.0 | c7c00b10cfc323646d66a42228e0b65c96931b6d | 8d61ed40d0bc85a604aa78965ed5dbcde1fe700a |
| v0.35.1 | 1da8a8e572060e82bb191269ecb95cb584aa7cf5 | 794c0ae95d1985b3090eff723be60867ae307321 |
| v0.36.0 | 854cd4a42f88bb68979f0fa0c5bea47dc7f5de03 | 4e08fe26538b4d455f5f155a35001c7fdc896888 |
| v0.37.0 | bc9f8e83a9853e9c7f1b2be3cb83a2090ebeadcc | 4c815c11e3c03858f954c9258d73dcaf410934ff |
| v0.37.1 | e0f05ebbc7a7c4e8117d03f6900d93aa310e9d81 | d84336fc81fc0e86173a93be8bf0e74b64972721 |
| v0.37.2 | 09bf72fce9a954f219e3ac3129ab83221fb21ff1 | 9174cef955b1603e5c52f5bb41341f826486e195 |
| v0.37.3 | 60798d610ebe263fb12bd83437309c39443c39bf | 1f8b80213ca1080c6bf35c394c2406bd2fdd11f8 |
| v0.37.4 | 6f3db36b83c7a3f8aa8d3ab187b91a5a6ac159cb | 0085341139a2999eb14b486680832014fd5c1f3f |
| v0.37.5 | dfdfae683357d7548a479fb37214e1f64770db10 | 8bc98f3d09e57c6a5882dbb59ca827805c3477a7 |
| v0.38.0 | 919f84238b81126f41630ed1bc6daa12342c3f51 | 27eae363a470fc7f8137f1bd4e6cffb2832f9454 |
| v0.38.1 | a56f12eca2b737e9d9210000ee599920001cc303 | e5efe256ffec6697ade71e1cdfb61212d61d5b3b |
| v0.38.2 | 373fd99edecab625cdfa492bdbeeaa4fd7b181ab | 9fe47ebda1565c670d45e0b49cb3e68aac17eab0 |
