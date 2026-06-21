# ATDD Specification: {{name}}

## 1. Problem Statement

- **Context:** {{context}}
- **The Gap / Bug:** {{bug}}
- **Impact:** {{impact}}

## 2. System Constraints & Environment

- **Runtime:** {{runtime}}
- **Frameworks:** {{frameworks}}
- **External Dependencies:** {{dependencies}}

## 3. Black-Box Test Cases (The "Green" Gates)

{% for scenario in scenarios %}
### Scenario {{loop.index}}: {{scenario.title}}

- **Given:** {{scenario.given}}
- **When:** {{scenario.when}}
- **Then:** {{scenario.then}}

{% endfor %}
## 4. Definition of Done (DoD)

- [ ] 100% of the above Scenarios implemented as automated integration tests.
- [ ] Regression testing passes (existing features remain unbroken).
- [ ] Code coverage for the affected modules meets or exceeds {{coverage}}%.
