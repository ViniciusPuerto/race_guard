Here are both diagrams — the **Class Diagram** first, then the **Event Flow**:

### Class Diagram
```visualizer
<script>
function loadScript(src, cb) {
  var s = document.createElement('script');
  s.src = src;
  s.onload = cb;
  document.head.appendChild(s);
}
loadScript('https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js', function() {
  mermaid.initialize({ startOnLoad: false, theme: 'neutral', fontSize: 13 });
  mermaid.render('class-diagram', document.getElementById('class-src').textContent.trim()).then(function(result) {
    document.getElementById('class-out').innerHTML = result.svg;
    var svg = document.getElementById('class-out').querySelector('svg');
    if (svg) { svg.style.width = '100%'; svg.style.height = 'auto'; }
  });
});
</script>

<pre id="class-src" style="display:none">
classDiagram
  class RaceGuard {
    +configure(block)
    +protect(name, block)
    +watch(klass, method)
    +define_rule(name, block)
    +after_commit(block)
    +report(event)
  }

  class Configuration {
    +enabled_detectors: Array
    +severity: Symbol
    +reporters: Array
    +ignored_models: Array
    +enable(detector)
    +severity(detector, level)
    +watch_commit_safety(type, block)
  }

  class Context {
    +thread_id: String
    +in_transaction: Boolean
    +protected_blocks: Array
    +current_rule: String
    +push(name)
    +pop()
    +in_transaction!()
    +clear_transaction!()
  }

  class RuleEngine {
    +rules: Hash
    +register(name, rule)
    +evaluate(context, event)
    +enabled?(name)
  }

  class Rule {
    +name: String
    +detector_block: Proc
    +message_block: Proc
    +severity: Symbol
    +detect(context)
    +message(context)
  }

  class Reporter {
    <<abstract>>
    +report(event)
  }

  class LogReporter {
    +report(event)
  }

  class JsonReporter {
    +report(event)
  }

  class WebhookReporter {
    +url: String
    +report(event)
  }

  class Event {
    +detector: String
    +message: String
    +severity: Symbol
    +location: String
    +thread_id: String
    +context: Hash
    +timestamp: Time
  }

  class DetectorBase {
    <<abstract>>
    +name: String
    +enabled: Boolean
    +setup()
    +teardown()
    +emit(event)
  }

  class CommitSafetyGuard {
    +interceptors: Array
    +setup()
    +patch_transaction()
    +patch_interceptors()
  }

  class DBLockAuditor {
    +watched_models: Array
    +setup()
    +patch_update()
    +lock_present?(context)
  }

  class IndexIntegrityAuditor {
    +models: Array
    +schema: SchemaParser
    +run()
    +compare()
  }

  class CVarWatcher {
    +trace: TracePoint
    +thread_map: Hash
    +setup()
    +on_cvasgn(event)
    +mutex_in_stack?()
  }

  class SchemaParser {
    +indexes: Hash
    +parse_schema_rb()
    +parse_live_db()
    +unique_indexes_for(table)
  }

  class MethodWrapper {
    +wrap(klass, method, block)
    +unwrap(klass, method)
    +wrapped?(klass, method)
  }

  RaceGuard --> Configuration
  RaceGuard --> Context
  RaceGuard --> RuleEngine
  RaceGuard --> Reporter
  RaceGuard --> DetectorBase

  RuleEngine --> Rule

  Reporter <|-- LogReporter
  Reporter <|-- JsonReporter
  Reporter <|-- WebhookReporter

  Reporter --> Event
  DetectorBase --> Event
  DetectorBase --> Reporter

  DetectorBase <|-- CommitSafetyGuard
  DetectorBase <|-- DBLockAuditor
  DetectorBase <|-- IndexIntegrityAuditor
  DetectorBase <|-- CVarWatcher

  IndexIntegrityAuditor --> SchemaParser
  CommitSafetyGuard --> MethodWrapper
  DBLockAuditor --> MethodWrapper
  CVarWatcher --> Context
  DetectorBase --> Context
  DetectorBase --> RuleEngine
</pre>

<div id="class-out" style="width:100%; overflow-x:auto; padding:8px 0;"></div>
```

### Event Flow
```visualizer
<script>
function loadScript(src, cb) {
  var s = document.createElement('script');
  s.src = src;
  s.onload = cb;
  document.head.appendChild(s);
}
loadScript('https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js', function() {
  mermaid.initialize({ startOnLoad: false, theme: 'neutral', fontSize: 13 });
  mermaid.render('event-flow', document.getElementById('flow-src').textContent.trim()).then(function(result) {
    document.getElementById('flow-out').innerHTML = result.svg;
    var svg = document.getElementById('flow-out').querySelector('svg');
    if (svg) { svg.style.width = '100%'; svg.style.height = 'auto'; }
  });
});
</script>

<pre id="flow-src" style="display:none">
sequenceDiagram
  autonumber
  participant App as App Code
  participant RG as RaceGuard
  participant CTX as Context
  participant DET as Detector
  participant RE as RuleEngine
  participant RPT as Reporter

  Note over App,RPT: Boot Phase
  App->>RG: RaceGuard.configure { }
  RG->>DET: setup() each enabled detector
  DET->>DET: patch target methods (MethodWrapper)
  RG->>RE: register rules
  RG->>RPT: initialize reporters

  Note over App,RPT: Runtime — RaceGuard.protect(:payment)
  App->>RG: RaceGuard.protect(:payment) { block }
  RG->>CTX: push(:payment)
  CTX->>CTX: set thread_id, timestamp

  App->>App: Order.transaction do
  App->>CTX: in_transaction! = true

  App->>App: OrderShippingJob.perform_later(id)
  DET->>DET: CommitSafetyGuard intercepts perform_later
  DET->>CTX: read in_transaction?
  CTX-->>DET: true

  DET->>RE: evaluate(:commit_safety, context)
  RE->>RE: run rule detector block
  RE-->>DET: violation detected

  DET->>RPT: emit(Event)
  RPT->>RPT: format message + location
  RPT-->>App: log/raise/webhook

  App->>App: end transaction
  App->>CTX: clear_transaction!

  App->>RG: end protect block
  RG->>CTX: pop(:payment)

  Note over App,RPT: Static Analysis — Rake Task
  App->>RG: rake race_guard:index_integrity
  RG->>DET: IndexIntegrity::Runner (or inline task)
  DET->>DET: ModelScanner.scan_file per app/models/**/*.rb
  DET->>DET: SchemaAnalyzer.parse_file(db/schema.rb) or from_connection
  DET->>DET: ComparisonEngine.missing_indexes
  DET->>RPT: STDOUT lines per violation + exit code
  RPT-->>App: report output (stdout / non-zero exit)
</pre>

<div id="flow-out" style="width:100%; overflow-x:auto; padding:8px 0;"></div>
```

---

### Key Takeaways from the Diagrams

**Class Diagram highlights:**
- `DetectorBase` is the abstract parent — all 4 detectors inherit from it, making it trivial to add new ones
- `MethodWrapper` is shared by `CommitSafetyGuard` and `DBLockAuditor` — no duplication
- `Reporter` is fully pluggable — `LogReporter`, `JsonReporter`, `WebhookReporter` all implement the same interface
- `RuleEngine` decouples detection logic from reporting — rules are first-class citizens

**Event Flow highlights:**
- Two distinct lifecycles: **Boot Phase** (patching) and **Runtime Phase** (detection)
- `Context` is the thread-local backbone — every detector reads from it
- The flow is: `App → Detector intercepts → Context check → RuleEngine evaluates → Reporter emits`
- Static analysis (Index Integrity) is a completely separate path — no runtime overhead

Want me to now write the **actual gem bootstrap code** based on this architecture?