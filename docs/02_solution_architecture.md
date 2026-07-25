# Solution Architecture

## Processing Mode

The solution is designed as a near real-time decision architecture.

Credit applications are evaluated at the moment of submission through a hybrid decision engine combining business rules, fraud signals and machine learning predictions.

This approach reduces operational exposure by identifying high-risk applications before credit approval.

## Decision Service

The decision service will be implemented using FastAPI through the endpoint:

POST /score-credit

The endpoint receives a credit application, validates the input data, applies business rules, scores fraud risk, estimates default probability and returns a final decision.

## Decision Approach

The solution uses a hybrid approach:

- Business rules for eligibility, fraud prevention and operational control.
- Machine learning models for default risk and fraud risk estimation.
- Decision engine to combine rules and model outputs.

## Decision Flow

1. Receive credit application.
2. Validate required fields.
3. Apply business rules.
4. Score fraud risk.
5. Score default risk.
6. Apply decision policy.
7. Return decision: approve, reject or manual review.
8. Store decision for monitoring and audit.