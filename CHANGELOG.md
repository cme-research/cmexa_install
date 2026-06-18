# Changelog

## [0.6.4](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.6.3...jazzy-v0.6.4) (2026-06-18)


### Bug Fixes

* **repos:** bump cmeresearch_bringup to a7d1096 ([94c4c5d](https://github.com/cme-research/cmexa_install/commit/94c4c5d889e60baaecbf6876a668af1e3609718d))
* **repos:** bump cmeresearch_bringup to a7d1096 ([e48e182](https://github.com/cme-research/cmexa_install/commit/e48e182bdd89738550543b7414ec2b5d3c3ab11e))

## [0.6.3](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.6.2...jazzy-v0.6.3) (2026-06-14)


### Bug Fixes

* **repos:** bump cmeresearch_bringup to bed0042 ([d3a562e](https://github.com/cme-research/cmexa_install/commit/d3a562e723f34d3d9165c59f55749fcf0aa2b887))
* **repos:** bump cmeresearch_bringup to bed0042 ([417f620](https://github.com/cme-research/cmexa_install/commit/417f620079d1b653d80602ae0b33323d54afe70c))

## [0.6.2](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.6.1...jazzy-v0.6.2) (2026-06-14)


### Bug Fixes

* **deploy,healthcheck:** force-recreate mosquitto and probe via eth0 … ([4e83b08](https://github.com/cme-research/cmexa_install/commit/4e83b080f51d007efd2a06d129ae988995360ab7))
* **repos:** bump cmeresearch_msgs to fe4c7f1 ([f225a49](https://github.com/cme-research/cmexa_install/commit/f225a495520f9b14a0f2e444fc77d53e8a7ed457))
* **repos:** bump cmeresearch_msgs to fe4c7f1 in nav.repos ([cce986c](https://github.com/cme-research/cmexa_install/commit/cce986cb4ee53b8822f5d0fa5167c29aa1f5b3df))
* **repos:** bump cmeresearch_robot_state to 93d75f5 ([bfb47e6](https://github.com/cme-research/cmexa_install/commit/bfb47e614762acaebe6f994e7e11e9ac95f1bf96))
* **repos:** bump cmeresearch_robot_state to 93d75f5 ([e54b8fa](https://github.com/cme-research/cmexa_install/commit/e54b8fa02dd1b1b8a0483d9c47949996acf3bbee))

## [0.6.1](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.6.0...jazzy-v0.6.1) (2026-06-12)


### Bug Fixes

* **deploy,healthcheck:** force-recreate mosquitto and probe via eth0 ([#35](https://github.com/cme-research/cmexa_install/issues/35)) ([#40](https://github.com/cme-research/cmexa_install/issues/40)) ([fe6c244](https://github.com/cme-research/cmexa_install/commit/fe6c244b1a286ba932414e56bc7428da0b4b212f))

## [0.6.0](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.5.2...jazzy-v0.6.0) (2026-06-04)


### Neue Features

* **repos:** bundle cmeresearch_robot_state in hardware image ([#36](https://github.com/cme-research/cmexa_install/issues/36)) ([6640ad7](https://github.com/cme-research/cmexa_install/commit/6640ad701fde9c07ef83b0935353733bddb4bb25))


### Bug Fixes

* **repos:** bump cmeresearch_bringup to c54406d ([#37](https://github.com/cme-research/cmexa_install/issues/37)) ([db38d5b](https://github.com/cme-research/cmexa_install/commit/db38d5ba71a60027e1668a2a9d9586cd2abf21a1))

## [0.5.2](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.5.1...jazzy-v0.5.2) (2026-05-30)


### Bug Fixes

* **repos:** bump cmeresearch_bringup to 7b6e831 ([b8adff5](https://github.com/cme-research/cmexa_install/commit/b8adff5a1a4733ab874130193e7bcfbf765cf346))
* **repos:** bump cmeresearch_bringup to 7b6e831 ([7a3e914](https://github.com/cme-research/cmexa_install/commit/7a3e914aba5606a76030d4e9a6c9c1525e121f7b))
* **repos:** bump cmeresearch_description to 5158b10 ([43ee23f](https://github.com/cme-research/cmexa_install/commit/43ee23f0eabe0485dc3c29a2d6b62c0095c27903))
* **repos:** bump cmeresearch_description to 5158b10 ([17b72cd](https://github.com/cme-research/cmexa_install/commit/17b72cd3a56bbb691c533d667450aeea55433438))

## [0.5.1](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.5.0...jazzy-v0.5.1) (2026-05-29)


### Bug Fixes

* **mosquitto:** bind listener to all interfaces, not just loopback ([70096e3](https://github.com/cme-research/cmexa_install/commit/70096e3140ed022e53026d7e01af7b2bead02d0e))
* **mosquitto:** bind listener to all interfaces, not just loopback ([bc84014](https://github.com/cme-research/cmexa_install/commit/bc8401468fd80d212b975ef1123920057fc0f619))

## [0.5.0](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.4.1...jazzy-v0.5.0) (2026-05-29)


### Neue Features

* **build:** pin sub-repo versions via SHA and consume through vcs import ([07221c1](https://github.com/cme-research/cmexa_install/commit/07221c19e8902928a7ee1e0c078b6367d0eea32e))
* **build:** pin sub-repo versions via SHA and consume through vcs import ([16a6f9d](https://github.com/cme-research/cmexa_install/commit/16a6f9df54df1d2317f7d523a4abc3fc32405e0d))
* **ci:** auto-bump sub-repo SHAs and open one PR per drifted repo ([39e2969](https://github.com/cme-research/cmexa_install/commit/39e296952376fe1965b76eef1d942bd6bc53731e))
* **ci:** auto-bump sub-repo SHAs and open one PR per drifted repo ([46f9a29](https://github.com/cme-research/cmexa_install/commit/46f9a2966f44b52b9e40fca17377df3aec591639))

## [0.4.1](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.4.0...jazzy-v0.4.1) (2026-05-27)


### Bug Fixes

* **docker:** auto-invalidate cache when source repo HEAD moves ([a9fdfa8](https://github.com/cme-research/cmexa_install/commit/a9fdfa86874fc196652727e47b9d085aa1acda2c))
* **docker:** auto-invalidate cache when source repo HEAD moves ([6bb3454](https://github.com/cme-research/cmexa_install/commit/6bb3454ed05ad2c697a5c3c1d85e8a5db0ca36b9))

## [0.4.0](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.3.0...jazzy-v0.4.0) (2026-05-27)


### Neue Features

* **deploy:** make nav stack optional via --nav flag ([58d364b](https://github.com/cme-research/cmexa_install/commit/58d364b5e730ccdd6a507be162ed45a2839cedb4))


### Bug Fixes

* **docker:** add localhost peer to cyclonedds config ([b86c454](https://github.com/cme-research/cmexa_install/commit/b86c45466549ca87d603006f2d2e3558f7b0b7e6))

## [0.3.0](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.2.0...jazzy-v0.3.0) (2026-05-26)


### Neue Features

* **compose:** gate nav on hardware healthcheck ([b5dccdd](https://github.com/cme-research/cmexa_install/commit/b5dccdd3eb05b18b221a9373b71efb315d3273c9))
* **compose:** gate nav startup on hardware healthcheck ([a115c91](https://github.com/cme-research/cmexa_install/commit/a115c91fe2c9d3c0987cb1ceb442cc11fef01a74))


### Bug Fixes

* **docker:** clone source repos from jazzy_dev to match cmexa_robot.repos ([b5a8199](https://github.com/cme-research/cmexa_install/commit/b5a819982a60cfedeb95919063ebd74836efe775))

## [0.2.0](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.1.1...jazzy-v0.2.0) (2026-05-26)


### Neue Features

* **brickd:** build TinkerForge brickd on GHCR ([7d8b2ff](https://github.com/cme-research/cmexa_install/commit/7d8b2ff48c116dc2fee8778a7d7daa5bbf7021f0))
* **brickd:** build TinkerForge brickd on GHCR ([6954594](https://github.com/cme-research/cmexa_install/commit/6954594c401225625ffaa994430b7d5433b336bc))


### Dokumentation

* **readme:** drop GHCR_TOKEN prerequisite (all images are public) ([79dcb62](https://github.com/cme-research/cmexa_install/commit/79dcb62754a91d23c4a2b132bbead7d524fda099))
* **readme:** drop GHCR_TOKEN prerequisite (all images are public) ([3985eb9](https://github.com/cme-research/cmexa_install/commit/3985eb98b50bb23316e5c9e246b783b6376d76b6))

## [0.1.1](https://github.com/cme-research/cmexa_install/compare/jazzy-v0.1.0...jazzy-v0.1.1) (2026-05-24)


### Dokumentation

* add release and CI badges ([5342e98](https://github.com/cme-research/cmexa_install/commit/5342e980e93e01be18add8a791d2211beec51a19))
* add release and CI badges to README ([8d2d93b](https://github.com/cme-research/cmexa_install/commit/8d2d93bc2279ef637b4b80d9634cff8ff94af50e))
