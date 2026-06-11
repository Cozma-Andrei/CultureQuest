# Structure

## Chapter 1 - Introduction
- **1.1 Context** - rise of location-based mobile apps for tourism/cultural
  discovery; privacy concerns around centralized ML on personal behavior data;
  Federated Learning as an alternative.
- **1.2 Problem Statement** - generic city-guide apps show the same
  landmarks/routes to everyone; personalization usually requires uploading raw
  interaction history to a server.
- **1.3 Objectives** - (a) mobile app for discovering cultural landmarks with
  proximity-based exploration and gamified quests, (b) personalize
  landmark/route recommendations per-user without raw data leaving the device,
  (c) implement the full FL pipeline (pretraining -> fine-tuning -> on-device
  FedAvg -> async aggregation with privacy guarantees).
- **1.4 Proposed Solution** (high level) - a Flutter mobile app for
  proximity-based discovery of cultural landmarks, with route generation and
  gamified quests; personalization is powered by a small on-device model
  (22->32->16->1 MLP) trained via privacy-preserving Federated Learning
  (FastAPI/MongoDB/Redis backend).
- **1.5 Results Obtained** (high level) - working app with map/routes/quests;
  pretrained+fine-tuned global model; simulation of FedAsync staleness
  discount over 600 rounds.
- **1.6 Thesis Structure** - 1-2 sentence summary of each chapter below.

## Chapter 2 - Requirements Analysis / Motivation
- **2.1 Target Users & Use Cases** - tourist/local exploring a city, wanting
  personalized landmark suggestions, routes, and gamified incentives (quests).
- **2.2 Functional Requirements** - map with nearby landmarks, route
  generation, quest system, ratings/reviews, profile + FL sync, privacy
  controls.
- **2.3 Non-Functional Requirements** - on-device privacy (no raw data leaves
  the phone), offline resilience (cached landmarks), low on-device training
  cost (small MLP), backend scalability for async client uploads, cold-start
  handling (new users and new landmarks must get useful recommendations from
  the pretrained global model and content-based features before any local FL
  personalization has occurred).
- **2.4 Project Scope** - what's covered vs out of scope (e.g., per-user
  personalization head listed as future work).

## Chapter 3 - Market Study / Existing Solutions
- **3.1 Existing Urban Exploration Apps** - Google Maps, TripAdvisor,
  city-guide apps; how they personalize (or don't) and their data-collection
  model.
- **3.2 Centralized vs Federated Recommendation Approaches** -
  collaborative/content-based filtering with server-side data vs FL; privacy
  tradeoffs.
- **3.3 Federated Learning: State of the Art** - FL taxonomy (Horizontal vs
  Vertical vs Federated Transfer Learning; Cross-Device vs Cross-Silo) used to
  position CultureQuest as **horizontal, cross-device FL**; FedAvg, async FL,
  robustness, and privacy (see Bibliography below for the survey papers
  backing this section).
- **3.4 Rejected Alternatives** - FedProx, SCAFFOLD, FedDyn: why their
  cross-client drift-correction terms assume synchronous multi-client rounds,
  which don't apply to CultureQuest's one-client-per-round async design.
- **3.5 Technology Stack & Justification**
  - 3.5.1 Flutter + Riverpod (vs React Native/native)
  - 3.5.2 FastAPI + MongoDB + Redis (vs alternatives)
  - 3.5.3 OSRM for routing
  - 3.5.4 Custom MLP vs TFLite/PyTorch Mobile (model size, no runtime
    dependency)

## Chapter 4 - Proposed Solution
- **4.1 System Overview** - architecture diagram: mobile client <-> FastAPI
  backend <-> MongoDB (persistent data) + Redis (FL state).
- **4.2 Mobile App Architecture** - feature-based Flutter structure (map,
  profile, federated, etc.), Riverpod state management.
- **4.3 Backend Architecture** - FastAPI services/routes, data model
  (landmarks, users, quests, routes, events).
- **4.4 Federated Learning System Design**
  - 4.4.1 Model Architecture (22 -> 32 -> 16 -> 1 MLP, sigmoid output, feature
    vector breakdown)
  - 4.4.2 Local Training (FedAvg client procedure: 5 local epochs, SGD)
  - 4.4.3 Asynchronous Aggregation & Staleness Discount (FedAsync:
    `n_effective = n_samples/(1+staleness)`)
  - 4.4.4 Clipped Aggregation (delta-norm clipping against adversarial/extreme
    updates)
  - 4.4.5 Differential Privacy (Gaussian noise on weight deltas)
  - 4.4.6 Concurrency Control (Redis aggregation lock)
- **4.5 Route Generation Pipeline** - FL score x 0.8 + proximity x 0.2
  filtering, interest-match tiebreaker, FL-scaled dwell time.
- **4.6 Gamification Design** - quest system and engagement labels (sheet
  opened, navigation started, quest completed, ratings).
- **4.7 Map & Navigation** - geofencing, compass/GPS-based map rotation.
- **4.8 Privacy Architecture** - what stays on-device vs what's uploaded;
  data-flow diagram.

## Chapter 5 - Implementation Details
- **5.1 Mobile Implementation** (UI-facing subsections include a
  representative app screenshot)
  - 5.1.1 FL Client Service - forward pass + manual backprop in Dart,
    gradient clipping
  - 5.1.2 Differential Privacy Noise Injection (Box-Muller Gaussian noise)
  - 5.1.3 Local Interaction Buffer & Persistence (SharedPreferences-based
    caching, survives app kills)
  - 5.1.4 Offline Landmark Caching
  - 5.1.5 Route Generation Algorithm - candidate filtering (FL score x 0.8 +
    proximity x 0.2), interest-match tiebreaker, FL-scaled dwell time per stop
  - 5.1.6 Quest System & Geofencing - quest completion detection, geofence
    triggers, engagement-label recording
- **5.2 Backend Implementation**
  - 5.2.1 Aggregation Service (`fedavg`, `clipped_fedavg`, staleness discount,
    Redis lock)
  - 5.2.2 API Endpoints (model fetch/update, status)
- **5.3 Pretraining Pipeline**
  - 5.3.1 Dataset Preparation (Foursquare TSMC2014/TIST2015, ubicomp2013,
    Yelp, synthetic data; label construction)
  - 5.3.2 Training From Scratch (MLP, SGD, LR decay)
  - 5.3.3 Fine-Tuning (data augmentation for low-label signal, hyperparameter
    changes, mean-reversion fix)
- **5.4 FL Simulation Framework** - synthetic multi-round simulation comparing
  FedAsync staleness discount on vs off, concept-drift modeling for stale
  clients.
- **5.5 Notable Implementation Challenges** - mean-reversion problem in
  pretraining and how fine-tuning addressed it; tuning the staleness discount.

## Chapter 6 - Evaluation
- **6.1 Functional Correctness** - app features work as specified (map,
  routes, quests, FL round auto-trigger at 15 interactions, profile sync),
  demonstrated with screenshots.
- **6.2 FL Model Performance**
  - 6.2.1 Pretraining Results (MSE, R^2, prediction range)
  - 6.2.2 Fine-Tuning Results (before/after comparison table)
  - 6.2.3 Simulation Results (loss curves, weight drift, staleness
    distribution, contextual probes over 600 rounds)
- **6.3 Privacy & Robustness Evaluation** - effect of DP noise on model
  utility; effect of clipping on adversarial-style updates.
- **6.4 Comparison & Discussion** - sync vs async FedAvg tradeoffs (straggler
  problem); positioning vs Chapter 3 alternatives.

## Chapter 7 - Conclusions
- **7.1 Summary** - objectives revisited against what was delivered.
- **7.2 Future Work** - per-user personalization head, FedBuff-style buffered
  aggregation if client participation clusters in time, larger
  model/architecture changes, real-user FL data collection at scale.

---

## Bibliography

### A. Papers

Ranked from most to least central to the thesis (implemented algorithms
first, background/future-work references last). Bibtex keys and source
locations are in `bibliography_sources.md`.

| Citation | Used for | Cited in |
|---|---|---|
| McMahan, B., Moore, E., Ramage, D., Hampson, S., & y Arcas, B. A. (2017). Communication-Efficient Learning of Deep Networks from Decentralized Data. *AISTATS 2017*. | Origin of FedAvg - the client-side local-training procedure and the weighted-average aggregation formula. | 3.3, 4.4.2 |
| Xie, C., Koyejo, S., & Gupta, I. (2019). Asynchronous Federated Optimization. *arXiv:1903.03934*. | FedAsync staleness discount (`n_effective = n_samples/(1+staleness)`), the core of CultureQuest's async aggregation. | 3.3, 4.4.3, 6.2.3 |
| Bonawitz, K., Eichner, H., Grieskamp, N., Huba, D., Ingerman, A., Ivanov, V., Kiddon, C., Konečný, J., Mazzocchi, S., McMahan, H. B., Van Overveldt, T., Petrou, D., Ramage, D., & Roselander, J. (2019). Towards Federated Learning at Scale: System Design. *Proceedings of the 2nd SysML Conference*. | Production-FL-systems justification for warm-starting the global model from pretrained weights instead of random initialisation - motivates the pretraining/fine-tuning pipeline and the cold-start requirement. | 1.1, 2.3, 5.3 |
| McMahan, H. B., Ramage, D., Talwar, K., & Zhang, L. (2018). Learning Differentially Private Recurrent Language Models. *ICLR 2018* (arXiv:1710.06963). | DP-FedAvg's clip-then-aggregate template - origin of the per-update L2-norm clipping bound used by `clipped_fedavg`; the noise-addition step itself follows the Local-DP variant below (Wei et al., 2020). | 4.4.4 |
| Wei, K., Li, J., Ding, M., Ma, C., Yang, H. H., Farokhi, F., Jin, S., Quek, T. Q. S., & Poor, H. V. (2020). Federated Learning with Differential Privacy: Algorithms and Performance Analysis. *IEEE Transactions on Information Forensics and Security*, 15. | NbAFL (Noising before Model Aggregation FL) - each client clips and adds calibrated Gaussian noise to its weight delta *before* transmission, so the server never sees a clean update; the actual Local-DP mechanism implemented by `_addDPNoise`, with the privacy-utility analysis behind the 6.3 evaluation. | 4.4.5, 6.3 |
| Kairouz, P., McMahan, H. B., et al. (2021). Advances and Open Problems in Federated Learning. *Foundations and Trends in Machine Learning*, 14(1-2). | Primary survey - covers FedAvg, async FL, DP, SecAgg, robustness, personalization, and the cross-device vs cross-silo deployment taxonomy. Co-authored by McMahan and Bonawitz. | 1.1, 3.3 (primary reference throughout) |
| Lyu, L., Yu, H., & Yang, Q. (2020). Threats to Federated Learning: A Survey. *arXiv:2003.02133*. | Threat-model rationale for clipped aggregation (poisoning/adversarial clients) and DP (privacy attacks). | 3.3, 4.4.4, 4.4.5, 6.3 |
| Shokri, R., Stronati, M., Song, C., & Shmatikov, V. (2017). Membership Inference Attacks Against Machine Learning Models. *IEEE S&P 2017*. | Motivates the DP noise step on weight deltas (mitigates membership inference). | 4.4.5, 6.3 |
| Yang, Q., Liu, Y., Chen, T., & Tong, Y. (2019). Federated Machine Learning: Concept and Applications. *ACM Transactions on Intelligent Systems and Technology*, 10(2), Article 12. | Canonical Horizontal / Vertical / Federated-Transfer-Learning taxonomy - establishes CultureQuest as **horizontal FL** (shared 22-dim feature space across all clients). | 3.3 |
| Li, T., Sahu, A. K., Zaheer, M., Sanjabi, M., Talwalkar, A., & Smith, V. (2020). Federated Optimization in Heterogeneous Networks. *MLSys 2020*. | FedProx - rejected alternative; basis for the 3.4 discussion of why proximal/drift-correction terms don't fit single-client-per-round async FL. | 3.4 |
| Karimireddy, S. P., Kale, S., Mohri, M., Reddi, S. J., Stich, S. U., & Suresh, A. T. (2020). SCAFFOLD: Stochastic Controlled Averaging for Federated Learning. *ICML 2020*. | SCAFFOLD - rejected alternative; its control-variate drift correction assumes a concurrent cohort training from the same checkpoint, which CultureQuest's one-client-per-round async design does not have (3.4). | 3.4 |
| Acar, D. A. E., Zhao, Y., Navarro, R. M., Mattina, M., Whatmough, P. N., & Saligrama, V. (2021). Federated Learning Based on Dynamic Regularization. *ICLR 2021*. | FedDyn - rejected alternative; its dynamic regulariser is rejected for the same reason as FedProx and SCAFFOLD (3.4). | 3.4 |
| Li, T., Sahu, A. K., Talwalkar, A., & Smith, V. (2020). Federated Learning: Challenges, Methods, and Future Directions. *IEEE Signal Processing Magazine*, 37(3). | General FL challenges (heterogeneity, communication, privacy), incl. cross-device vs cross-silo framing; context for the FedProx discussion above (overlapping authors). | 3.3, 3.4 |
| Zhang, C., Xie, Y., Bai, H., Yu, B., Li, W., & Gao, Y. (2021). A survey on federated learning. *Knowledge-Based Systems*, 216, 106775. | General FL background/taxonomy. | 1.1, 3.3 (intro) |
| Li, L., Fan, Y., Tse, M., & Lin, K.-Y. (2020). A review of applications in federated learning. *Computers & Industrial Engineering*, 149, 106854. | Application-domain motivation (mobile/IoT FL use cases). | 1.1 (Context) |
| Arivazhagan, M. G., Aggarwal, V., Singh, A. K., & Choudhary, S. (2019). Federated Learning with Personalization Layers. *arXiv:1912.00818*. | FedPer - splits the model into shared backbone layers (federated via FedAvg) and local personalization layers (kept on-device, never uploaded); the architecture proposed for the future-work "personal head". | 2.4, 7.2 |
| Bonawitz, K., Ivanov, V., Kreuter, B., Marcedone, A., McMahan, H. B., Patel, S., Ramage, D., Segal, A., & Seth, K. (2017). Practical Secure Aggregation for Privacy-Preserving Machine Learning. *ACM CCS 2017*. | SecAgg - discussed as a complementary, not-yet-implemented protocol (server only sees the sum of updates). | 4.8, 7.2 |
| Nguyen, J., Malik, K., Zhan, H., Yousefpour, A., Rabbat, M., Malek, M., & Huba, D. (2022). Federated Learning with Buffered Asynchronous Aggregation (FedBuff). *arXiv:2106.06639*. | Buffered async aggregation - considered as a middle ground between sync FedAvg and pure async; flagged as future work. | 3.3, 7.2 |

### B. Datasets

Bibtex keys and source locations are in `bibliography_sources.md`.

| Citation | Used for | Cited in |
|---|---|---|
| Yang, D., Zhang, D., Zheng, V. W., & Yu, Z. (2015). Modeling User Activity Preference by Leveraging User Spatial Temporal Characteristics in LBSNs. *IEEE Transactions on Systems, Man, and Cybernetics: Systems*, 45(1). | TSMC2014 dataset (Foursquare NYC + Tokyo check-ins). | 5.3.1 |
| Yang, D., Zhang, D., & Qu, B. (2016). Participatory Cultural Mapping Based on Collective Behavior Data in Location-Based Social Networks. *ACM Transactions on Intelligent Systems and Technology*, 7(3). | TIST2015 dataset (global Foursquare check-ins). | 5.3.1 |
| Yang, D., Zhang, D., Yu, Z., & Yu, Z. (2013). Fine-Grained Preference-Aware Location Search Leveraging Crowdsourced Digital Footprints from LBSNs. *UbiComp 2013*. | ubicomp2013 dataset (NYC restaurant check-ins/tips). | 5.3.1 |
| Yelp Inc. Yelp Open Dataset. (academic license). | Yelp reviews - source of explicit negative-sentiment labels (1-2 star reviews). | 5.3.1 |

---

## Appendices
- Code excerpts (FL client forward/backprop, aggregation formula)
- Additional app screenshots (alternate states, edge cases not shown in 5.1)
- Full charts that don't fit inline (dataset overview, contextual probes,
  simulation plots)
