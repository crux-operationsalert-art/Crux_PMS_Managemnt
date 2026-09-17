-- The dossier content: accountabilities, what the chair is measured on,
-- what it may decide alone, what it must escalate, and its task tree.
create temp table _dos(code text, kind text, i int, j int, s text) on commit drop;
insert into _dos select split_part(x,'~',1), split_part(x,'~',2), split_part(x,'~',3)::int,
       split_part(x,'~',4)::int, split_part(x,'~',5)
from unnest(string_to_array($doc$BRD~ACC~1~0~Strategy and annual plan
BRD~ACC~2~0~Capital above the MD limit
BRD~ACC~3~0~Statutory standing
BRD~ACC~4~0~MD accountability
BRD~MEA~1~0~Revenue against plan
BRD~MEA~2~0~Clean statutory audit
BRD~MEA~3~0~Zero material compliance breach
BRD~DEC~1~0~All reserved matters
BRD~ESC~1~0~—
BRD~TSK~1~0~Governance
BRD~SUB~1~1~Quarterly business review
BRD~SUB~1~2~Approve budget and expansion
BRD~SUB~1~3~Review audit and compliance findings
MD~ACC~1~0~Company P&L
MD~ACC~2~0~New client empanelment and all pricing
MD~ACC~3~0~Partner agreements
MD~ACC~4~0~Organisation design and senior appointments
MD~MEA~1~0~Revenue vs plan
MD~MEA~2~0~EBITDA
MD~MEA~3~0~Branches operational vs plan
MD~MEA~4~0~Share of issues resolved below MD level
MD~DEC~1~0~Spend to Rs25,00,000 (proposed)
MD~DEC~2~0~All pricing and discount
MD~DEC~3~0~Appoint to function head
MD~ESC~1~0~Capital above limit · material litigation · data breach · auditor qualification — Board
MD~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
MD~TSK~1~0~Lead the executive team
MD~SUB~1~1~Weekly function head review
MD~SUB~1~2~Monthly business review
MD~SUB~1~3~Quarterly Board review
MD~TSK~2~0~Commercial approval
MD~SUB~2~1~Approve every empanelment and price
MD~SUB~2~2~Sign partner agreements
MD~SUB~2~3~Arbitrate cross-function conflict
OPS~ACC~1~0~National SLA and TAT
OPS~ACC~2~0~Capacity and cost per case
OPS~ACC~3~0~Field agency network
OPS~ACC~4~0~Collection target achievement across all regions
OPS~ACC~5~0~Branch and zone launch execution
OPS~MEA~1~0~TAT adherence at or above 95%
OPS~MEA~2~0~Escalation ratio below 2%
OPS~MEA~3~0~Cost per case
OPS~MEA~4~0~Audit score at or above 95%
OPS~DEC~1~0~Spend to Rs10,00,000 (proposed)
OPS~DEC~2~0~Empanel and terminate field agencies
OPS~DEC~3~0~Reallocate staff across regions
OPS~ESC~1~0~Top-5 client at risk · material SLA breach · integrity incident — MD
OPS~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
OPS~TSK~1~0~Run the network
OPS~SUB~1~1~Weekly regional roll-up
OPS~SUB~1~2~Monthly regional P&L review
OPS~SUB~1~3~Daily exception and ageing review
OPS~TSK~2~0~Agency and vendor
OPS~SUB~2~1~Empanelment, review, termination
OPS~SUB~2~2~SLA enforcement
OPS~SUB~2~3~Cost per case management
OPS~TSK~3~0~Expansion
OPS~SUB~3~1~Execute launches against the playbook
OPS~SUB~3~2~Site readiness, staffing, go-live
AVP~ACC~1~0~Four-region delivery outcome
AVP~ACC~2~0~Regional Manager development and bench
AVP~ACC~3~0~Partner versus branch client arbitration
AVP~ACC~4~0~Growth and expansion pipeline
AVP~MEA~1~0~Revenue vs target across four regions
AVP~MEA~2~0~Share of branches at target
AVP~MEA~3~0~Escalations resolved without the Operations Head
AVP~DEC~1~0~Spend to Rs7,50,000 (proposed)
AVP~DEC~2~0~Approve termination (AVP and above)
AVP~DEC~3~0~Cross-region reallocation
AVP~DEC~4~0~Arbitrate partner conflict
AVP~ESC~1~0~Top-5 client risk · partner contractual dispute · integrity incident — Operations Head
AVP~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
AVP~TSK~1~0~Regional oversight
AVP~SUB~1~1~Weekly roll-up from each Regional Manager
AVP~SUB~1~2~Monthly regional P&L walkthrough
AVP~SUB~1~3~Quarterly calibration with the Operations Head
AVP~TSK~2~0~Client and conflict
AVP~SUB~2~1~Arbitrate partner versus branch pursuit — company branch takes precedence
AVP~SUB~2~2~Senior client relationships across regions
AVP~TSK~3~0~People
AVP~SUB~3~1~Develop Regional Managers to autonomy
AVP~SUB~3~2~Succession bench per region
RM~ACC~1~0~Regional P&L and revenue
RM~ACC~2~0~Regional client relationships, renewals and expansion
RM~ACC~3~0~Regional DSO and ageing escalation
RM~ACC~4~0~Branch Manager performance, development and succession
RM~ACC~5~0~Branch quality remediation and audit closure
RM~ACC~6~0~Branch expansion proposals
RM~ACC~7~0~Regional review cadence and action closure
RM~ACC~8~0~Franchise partner performance and territory conduct in the region
RM~MEA~1~0~Regional revenue vs target
RM~MEA~2~0~Share of branches at target
RM~MEA~3~0~Mandate renewal rate
RM~MEA~4~0~Regional DSO vs Finance target
RM~MEA~5~0~Branch quality score
RM~MEA~6~0~Regrettable attrition
RM~DEC~1~0~Spend to Rs5,00,000 (evidenced)
RM~DEC~2~0~Hire Branch Managers within band
RM~DEC~3~0~Cross-branch reallocation in region
RM~ESC~1~0~Any pricing — MD only · termination — AVP and above · branch opening — Operations Head
RM~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
RM~TSK~1~0~Operations
RM~SUB~1~1~Regional delivery, TAT and productivity
RM~SUB~1~2~Capacity planning across branches
RM~SUB~1~3~Escalation management
RM~SUB~1~4~Weekly branch performance review
RM~TSK~2~0~Commercial and client
RM~SUB~2~1~Regional client relationships and renewals
RM~SUB~2~2~Service quality and escalation ownership
RM~SUB~2~3~Expansion within existing clients
RM~SUB~2~4~Pricing recommendation to MD — no discount authority
RM~TSK~3~0~Collections
RM~SUB~3~1~Follow-up against Finance-set targets
RM~SUB~3~2~Ageing escalation
RM~SUB~3~3~Dispute identification and routing to Credit Control
RM~TSK~4~0~People
RM~SUB~4~1~Branch Manager calibration
RM~SUB~4~2~Leadership development and succession
RM~SUB~4~3~Staffing plan and attrition control
RM~TSK~5~0~Quality and growth
RM~SUB~5~1~Remediation of audit findings
RM~SUB~5~2~Corrective action closure
RM~SUB~5~3~Branch expansion business case
RM~TSK~6~0~Franchise partners
RM~SUB~6~1~Monthly performance review with each partner firm
RM~SUB~6~2~Territory and conflict management, company branch takes precedence
RM~SUB~6~3~Confirm claim-supporting data before it goes to Finance
RM~SUB~6~4~Recommend continuation, expansion or exit
BM~ACC~1~0~Branch P&L and revenue
BM~ACC~2~0~Branch collections and DSO
BM~ACC~3~0~Branch budget and ledger reconciliation
BM~ACC~4~0~Client servicing at branch level
BM~ACC~5~0~Field executive deployment and productivity
BM~ACC~6~0~Team stability and engagement
BM~ACC~7~0~Branch quality and compliance
BM~MEA~1~0~Branch revenue vs target
BM~MEA~2~0~New business acquired
BM~MEA~3~0~Branch DSO and ageing beyond 60 days
BM~MEA~4~0~Budget variance
BM~MEA~5~0~TAT adherence
BM~MEA~6~0~Report accuracy
BM~MEA~7~0~Regrettable attrition
BM~DEC~1~0~Spend to Rs10,000 (evidenced)
BM~DEC~2~0~Hire field executives within band
BM~DEC~3~0~Branch operational SLAs
BM~DEC~4~0~Warnings up to executive level
BM~ESC~1~0~New mandates and any pricing — MD · termination — AVP and above · expenses above limit — Regional Manager
BM~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
BM~TSK~1~0~Grow the book
BM~SUB~1~1~Activate dormant accounts
BM~SUB~1~2~Local new business
BM~SUB~1~3~Revenue per client growth
BM~SUB~1~4~Weekly client review
BM~TSK~2~0~Daily operations
BM~SUB~2~1~Case allocation oversight
BM~SUB~2~2~TAT and productivity monitoring
BM~SUB~2~3~Field and back-office coordination
BM~TSK~3~0~Field deployment
BM~SUB~3~1~Plan daily deployment by geography and case type
BM~SUB~3~2~Monitor field productivity
BM~SUB~3~3~Coach low performers weekly
BM~TSK~4~0~Collections
BM~SUB~4~1~Weekly collection status
BM~SUB~4~2~Work receivables beyond 60 days
BM~SUB~4~3~Escalate disputes early
BM~TSK~5~0~Books and people
BM~SUB~5~1~Monthly expense reconciliation
BM~SUB~5~2~Ledger reconciliation before regional review
BM~SUB~5~3~Weekly team pulse
BM~SUB~5~4~Develop the Team Leader to cover 72 hours
TL~ACC~1~0~Daily processing target
TL~ACC~2~0~Workload distribution
TL~ACC~3~0~TAT and ageing control
TL~ACC~4~0~Data accuracy and MIS
TL~ACC~5~0~Back-office supervision
TL~MEA~1~0~Daily target at or above 95%
TL~MEA~2~0~Output per executive vs benchmark
TL~MEA~3~0~Share of cases within TAT
TL~MEA~4~0~Error rate below 3%
TL~MEA~5~0~Timely MIS submission
TL~DEC~1~0~Spend to Rs2,500 (proposed)
TL~DEC~2~0~Daily allocation and reallocation within the team
TL~ESC~1~0~Any case at TAT risk — same working day · repeated underperformance — Branch Manager
TL~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
TL~TSK~1~0~Daily target
TL~SUB~1~1~Allocate tasks and portfolios
TL~SUB~1~2~Monitor real-time performance
TL~SUB~1~3~Mid-day and end-of-day review
TL~SUB~1~4~Coach low performers
TL~TSK~2~0~TAT and ageing
TL~SUB~2~1~Track ageing and pending buckets
TL~SUB~2~2~Prioritise SLA-bound work
TL~SUB~2~3~Same-day escalation of delays
TL~TSK~3~0~Data and MIS
TL~SUB~3~1~Error-free system updates
TL~SUB~3~2~Verify reports before submission
TL~SUB~3~3~Daily and weekly MIS within timeline
TL~SUB~3~4~Maintain audit trail
BO~ACC~1~0~Case processing accuracy
BO~ACC~2~0~Report preparation within TAT
BO~ACC~3~0~System record and audit trail integrity
BO~MEA~1~0~Cases processed per day
BO~MEA~2~0~Share within TAT
BO~MEA~3~0~Error rate below 3%
BO~MEA~4~0~Rejection or rework count
BO~DEC~1~0~No financial authority
BO~ESC~1~0~Incomplete or contradictory field input · portal failure blocking submission
BO~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
BO~TSK~1~0~Case processing
BO~SUB~1~1~Receive and log allocation
BO~SUB~1~2~Compile field inputs
BO~SUB~1~3~Prepare the verification report
BO~SUB~1~4~Upload to the client portal within TAT
BO~TSK~2~0~Records
BO~SUB~2~1~Documentation completeness
BO~SUB~2~2~Flag contradictory field input
CE~ACC~1~0~Local certification of completed cases at the client''s branch
CE~ACC~2~0~Invoice approval obtained from the client''s local officer
CE~ACC~3~0~Handover of certified accounts to the central collections team
CE~ACC~4~0~Days from case completion to certification
CE~MEA~1~0~Days from case completion to local certification
CE~MEA~2~0~Certification rate against cases billed
CE~MEA~3~0~Accounts handed to central with complete evidence
CE~MEA~4~0~Local queries resolved within SLA
CE~DEC~1~0~No financial authority
CE~ESC~1~0~Any account beyond 60 days
CE~ESC~2~0~Any client disputing an invoice
CE~ESC~3~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
CE~TSK~1~0~Local certification
CE~SUB~1~1~Follow up with the client''s branch or regional officer for case certification
CE~SUB~1~2~Obtain invoice approval or sign-off
CE~SUB~1~3~Resolve documentation queries raised locally
CE~TSK~2~0~Handover
CE~SUB~2~1~Pass certified accounts to the central collections team with evidence
CE~SUB~2~2~Flag anything the local officer will not certify, with the reason
BDE~ACC~1~0~New business from the branch territory
BDE~ACC~2~0~Dormant account activation
BDE~ACC~3~0~Local client relationship at working level
BDE~MEA~1~0~New business from the territory
BDE~MEA~2~0~Account activation rate
BDE~MEA~3~0~Revenue per client growth
BDE~MEA~4~0~Leads passed and converted
BDE~DEC~1~0~No pricing authority — any price goes to the MD
BDE~ESC~1~0~Any pricing or commercial term — head office
BDE~ESC~2~0~Client at risk of loss
BDE~ESC~3~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
BDE~TSK~1~0~Acquisition
BDE~SUB~1~1~Identify and approach local branches of empanelled banks
BDE~SUB~1~2~Activate dormant accounts
BDE~SUB~1~3~Pass qualified leads to Business Development at head office
BDE~TSK~2~0~Relationship
BDE~SUB~2~1~Routine client contact at the operating level
BDE~SUB~2~2~Collect service feedback
BDE~SUB~2~3~Flag renewal risk early
FE~ACC~1~0~Case completion within TAT
FE~ACC~2~0~Accuracy and authenticity of field findings
FE~ACC~3~0~SOP adherence without deviation
FE~ACC~4~0~Honest reporting of adverse findings
FE~MEA~1~0~Cases per day vs product benchmark
FE~MEA~2~0~Share of cases within TAT
FE~MEA~3~0~Error rate
FE~MEA~4~0~Fraud indicators correctly escalated
FE~MEA~5~0~Zero SOP deviation
FE~DEC~1~0~No financial authority
FE~ESC~1~0~Any case that cannot meet TAT — same day · suspected fraud — immediately
FE~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
FE~TSK~1~0~Field verification
FE~SUB~1~1~Visit and verify at the address
FE~SUB~1~2~Capture evidence per client SOP
FE~SUB~1~3~Record findings accurately
FE~SUB~1~4~Submit within TAT
FE~TSK~2~0~Risk detection
FE~SUB~2~1~Identify document tampering and fraud indicators
FE~SUB~2~2~Escalate suspected fraud immediately, bypassing the branch if needed
FE~SUB~2~3~Resist inducement and record any approach
PA~ACC~1~0~Business generated from the franchise territory
PA~ACC~2~0~Collection on franchise-sourced accounts
PA~ACC~3~0~Delivery to the same SLA, TAT and quality standard as a company branch
PA~ACC~4~0~Brand and SOP conformance at the franchise location
PA~ACC~5~0~Monthly claim submitted with complete supporting evidence
PA~MEA~1~0~Franchise revenue against agreed plan
PA~MEA~2~0~File TAT against branch SLA
PA~MEA~3~0~Quality score on franchise files
PA~MEA~4~0~Collection on sourced accounts
PA~MEA~5~0~Brand and SOP audit score
PA~MEA~6~0~Claim accuracy against computed entitlement
PA~DEC~1~0~Client outreach within the agreed territory
PA~DEC~2~0~Own hiring, pay and internal structure — entirely their own
PA~ESC~1~0~Any pricing or commercial term — the Managing Director
PA~ESC~2~0~Territory or scope change — the Managing Director
PA~ESC~3~0~Conflict with a company branch over a client — the AVP arbitrates, company branch takes precedence
PA~ESC~4~0~Any client data or brand incident — Assurance immediately
PA~ESC~5~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
PA~TSK~1~0~Business
PA~SUB~1~1~Client acquisition within the agreed territory
PA~SUB~1~2~Account activation and revenue growth
PA~SUB~1~3~Local business development at the working level
PA~TSK~2~0~Delivery
PA~SUB~2~1~Meet branch-equivalent SLA, TAT and quality
PA~SUB~2~2~Follow client SOPs without deviation
PA~SUB~2~3~Protect client data to the same standard required of employees
PA~TSK~3~0~Brand and conduct
PA~SUB~3~1~Operate within Crux brand guidelines
PA~SUB~3~2~Submit to periodic brand and SOP audit
PA~SUB~3~3~Declare any conflict with a competing mandate
PA~TSK~4~0~Claim
PA~SUB~4~1~Submit the monthly claim by the agreed date
PA~SUB~4~2~Attach case, billing and collection evidence
PA~SUB~4~3~Respond to variance queries within the agreed window
BZ~ACC~1~0~South zone revenue against target
BZ~ACC~2~0~Zone collections and ageing
BZ~ACC~3~0~Branch performance across the zone
BZ~ACC~4~0~Client retention in zone
BZ~MEA~1~0~Zone revenue vs target
BZ~MEA~2~0~TAT adherence
BZ~MEA~3~0~Collection target achievement
BZ~MEA~4~0~Audit score
BZ~MEA~5~0~Attrition
BZ~DEC~1~0~Spend to Rs1,00,000 (proposed)
BZ~DEC~2~0~Branch staffing decisions within budget
BZ~ESC~1~0~Any pricing — MD only · termination — AVP and above
BZ~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
BZ~TSK~1~0~Zone business
BZ~SUB~1~1~Revenue and productivity against zone plan
BZ~SUB~1~2~Branch performance ranking
BZ~SUB~1~3~Capacity and allocation
BZ~TSK~2~0~Collections
BZ~SUB~2~1~Execute the collection target set by Finance
BZ~SUB~2~2~Ageing follow-up
BZ~SUB~2~3~Dispute escalation to Credit Control
BZ~TSK~3~0~People
BZ~SUB~3~1~Branch team productivity
BZ~SUB~3~2~Attrition control
BZ~SUB~3~3~Field coaching visits
ADM~ACC~1~0~Office and infrastructure functioning
ADM~ACC~2~0~Asset reconciliation
ADM~ACC~3~0~Travel and expense policy enforcement
ADM~ACC~4~0~Admin vendor SLA
ADM~MEA~1~0~Asset reconciliation status
ADM~MEA~2~0~Office downtime
ADM~MEA~3~0~Vendor SLA compliance
ADM~MEA~4~0~Expense policy deviations
ADM~DEC~1~0~Spend to Rs50,000 (proposed)
ADM~DEC~2~0~Empanel admin vendors within the approved list
ADM~ESC~1~0~Asset loss or unreconciled variance · vendor failure affecting operations
ADM~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
ADM~TSK~1~0~Facilities
ADM~SUB~1~1~Lease, utilities, security, housekeeping
ADM~SUB~1~2~Office readiness for new locations
ADM~TSK~2~0~Assets and vendors
ADM~SUB~2~1~Tagging, tracking, annual verification
ADM~SUB~2~2~Vendor empanelment and SLA
ADM~SUB~2~3~Expense claim scrutiny
CCM~ACC~1~0~Collection target achievement across both stages
CCM~ACC~2~0~One ageing report showing which stage every rupee is stuck at
CCM~ACC~3~0~Portfolio allocation across central and branch executives
CCM~ACC~4~0~Credit control operation and limit breach flagging
CCM~ACC~5~0~Dispute and deduction resolution
CCM~ACC~6~0~Collection method, cadence and escalation standard for both teams
CCM~MEA~1~0~Collection efficiency at or above 95%
CCM~MEA~2~0~DSO at or below 45 days
CCM~MEA~3~0~AR beyond 90 days below 5%
CCM~MEA~4~0~Dispute resolution within SLA
CCM~DEC~1~0~Spend to Rs1,00,000 (proposed)
CCM~DEC~2~0~Allocate collection portfolios
CCM~DEC~3~0~Escalate any account to Operations for field follow-up
CCM~ESC~1~0~Service suspension · credit limit change · write-off — Finance Head
CCM~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
CCM~TSK~1~0~Run the two stages
CCM~SUB~1~1~Stage 1 — branch executives obtain local certification and invoice approval at the bank''s branch
CCM~SUB~1~2~Stage 2 — central executives submit to the bank''s payables desk and pursue release
CCM~SUB~1~3~Move an account from stage 1 to stage 2 only when local certification is obtained
CCM~SUB~1~4~Track both stages on a single ageing report
CCM~TSK~2~0~Allocate and set the standard
CCM~SUB~2~1~Allocate client portfolios to central executives
CCM~SUB~2~2~Allocate territory accounts to branch executives through the Branch Manager
CCM~SUB~2~3~Set the call cadence, commitment log format and escalation ladder for both teams
CCM~TSK~3~0~Credit control
CCM~SUB~3~1~Operate the limits set by Finance
CCM~SUB~3~2~Flag breaches before service continues
CCM~SUB~3~3~Recommend suspension for chronic defaulters
CCM~TSK~4~0~Disputes
CCM~SUB~4~1~Log and route billing disputes
CCM~SUB~4~2~Reconcile TDS, GST and client deductions
CCM~SUB~4~3~Escalate anything unresolved past its date
CCE~ACC~1~0~Payment release against the assigned client portfolio
CCE~ACC~2~0~Invoice submission and portal upload to the client''s payables desk
CCE~ACC~3~0~TDS, GST and deduction reconciliation
CCE~ACC~4~0~Receipt logging and allocation accuracy
CCE~ACC~5~0~Dispute documentation and follow-through
CCE~MEA~1~0~Portfolio collection against target
CCE~MEA~2~0~Days from certification to receipt
CCE~MEA~3~0~Deduction reconciliation completeness
CCE~MEA~4~0~Dispute logging completeness
CCE~DEC~1~0~No financial authority
CCE~ESC~1~0~Any account beyond 60 days · any client disputing an invoice
CCE~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
CCE~TSK~1~0~Release follow-up
CCE~SUB~1~1~Submit certified invoices to the client''s payables desk
CCE~SUB~1~2~Upload to the client vendor portal
CCE~SUB~1~3~Follow up for the payment date and maintain the commitment log
CCE~SUB~1~4~Escalate any account crossing 60 days from certification
CCE~TSK~2~0~Reconciliation
CCE~SUB~2~1~Reconcile TDS, GST and client deductions against the ledger
CCE~SUB~2~2~Log receipts against invoices
CCE~SUB~2~3~Document every dispute with evidence
FIN~ACC~1~0~DSO and collection target achievement
FIN~ACC~2~0~Customer credit limits and service suspension
FIN~ACC~3~0~Financial reporting and statutory accounts
FIN~ACC~4~0~Budget and cash flow
FIN~MEA~1~0~Budget variance within plus or minus 5%
FIN~MEA~2~0~DSO at or below 45 days
FIN~MEA~3~0~Collection efficiency at or above 95%
FIN~MEA~4~0~AR beyond 90 days below 5%
FIN~MEA~5~0~Closure within 7 to 10 days
FIN~DEC~1~0~Spend to Rs10,00,000 (proposed)
FIN~DEC~2~0~Set credit limits
FIN~DEC~3~0~Suspend service to a defaulting client
FIN~DEC~4~0~Set collection targets by region
FIN~ESC~1~0~Bad debt above tolerance · suspected irregularity · auditor qualification — MD and Board
FIN~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
FIN~TSK~1~0~Planning and control
FIN~SUB~1~1~Annual budget and quarterly forecast
FIN~SUB~1~2~Branch and regional profitability
FIN~SUB~1~3~Variance analysis
FIN~TSK~2~0~Order to cash
FIN~SUB~2~1~Set the collection targets Operations executes against
FIN~SUB~2~2~Own AR ageing and DSO
FIN~SUB~2~3~Set credit limits and suspension policy
FIN~TSK~3~0~Reporting
FIN~SUB~3~1~Monthly closure within 7 to 10 days
FIN~SUB~3~2~Cash flow forecasting
FIN~SUB~3~3~Financial MIS to MD and Board
ACC~ACC~1~0~Client invoicing and billing accuracy
ACC~ACC~2~0~AR ledger integrity and receipt allocation
ACC~ACC~3~0~Partner revenue-share computation and settlement
ACC~ACC~4~0~GST, TDS, Income Tax and PT
ACC~ACC~5~0~Month and year-end closing
ACC~MEA~1~0~Closure within timeline
ACC~MEA~2~0~Zero material accounting errors
ACC~MEA~3~0~Invoices within SLA
ACC~MEA~4~0~Zero revenue leakage
ACC~MEA~5~0~100% filings within due dates
ACC~MEA~6~0~Partner settlement accuracy
ACC~DEC~1~0~Spend to Rs2,00,000 (proposed)
ACC~DEC~2~0~Raise and issue invoices
ACC~DEC~3~0~Process partner settlement within terms
ACC~ESC~1~0~Suspected irregularity — Finance Head and MD immediately · tax notice — Finance Head
ACC~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
ACC~TSK~1~0~Accounting
ACC~SUB~1~1~Books per accounting standards
ACC~SUB~1~2~Month, quarter and year-end closing
ACC~SUB~1~3~P&L, Balance Sheet, Cash Flow
ACC~TSK~2~0~Billing
ACC~SUB~2~1~Timely and accurate invoicing
ACC~SUB~2~2~Verify billing against contracts and case data
ACC~TSK~3~0~Partner settlement
ACC~SUB~3~1~Compute the share monthly from billing data
ACC~SUB~3~2~Reconcile against partner records
ACC~SUB~3~3~Raise the payable
ACC~SUB~3~4~Maintain dispute log and working papers
ACC~TSK~4~0~Statutory
ACC~SUB~4~1~Filings within due dates
ACC~SUB~4~2~Coordinate auditors
ACC~SUB~4~3~Support internal and client audits
ACE~ACC~1~0~Transaction processing accuracy
ACE~ACC~2~0~Bank and ledger reconciliation
ACE~ACC~3~0~Partner share working papers
ACE~MEA~1~0~Processing accuracy
ACE~MEA~2~0~Reconciliation on schedule
ACE~MEA~3~0~Settlement accuracy
ACE~MEA~4~0~Rework count
ACE~DEC~1~0~No financial authority
ACE~ESC~1~0~Unreconciled item beyond tolerance · any entry that appears irregular
ACE~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
ACE~TSK~1~0~Processing
ACE~SUB~1~1~Book entries accurately and on time
ACE~SUB~1~2~Bank and ledger reconciliation
ACE~SUB~1~3~Vendor payment processing
ACE~TSK~2~0~Settlement
ACE~SUB~2~1~Extract partner-attributed billing
ACE~SUB~2~2~Apply the agreed share
ACE~SUB~2~3~Retain computation working papers
FEX~ACC~1~0~To be defined by the Finance Head, or the chair merges into Accounts or Credit & Collections
FEX~MEA~1~0~To be defined
FEX~DEC~1~0~No financial authority pending definition
FEX~ESC~1~0~As defined
FEX~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
FEX~TSK~1~0~Undefined
FEX~SUB~1~1~Finance Head to define or merge within 30 days
FEX~SUB~1~2~Do not invent an output for this chair
GRC~ACC~1~0~Report quality score and defect rate
GRC~ACC~2~0~Regulatory and client compliance
GRC~ACC~3~0~Independent audit across delivery, finance and the partner channel
GRC~ACC~4~0~Partner brand and SOP audit
GRC~ACC~5~0~Background verification of own employees and agents
GRC~ACC~6~0~Client audit response and observation closure
GRC~MEA~1~0~Report accuracy at or above 98%
GRC~MEA~2~0~SOP compliance at or above 95%
GRC~MEA~3~0~Zero critical compliance breach
GRC~MEA~4~0~Audit observations closed within timeline
GRC~MEA~5~0~Vacancy closure TAT
GRC~MEA~6~0~Payroll accuracy
GRC~DEC~1~0~Spend to Rs3,00,000 (proposed)
GRC~DEC~2~0~Audit any function without notice
GRC~DEC~3~0~Halt dispatch of a report failing the quality gate
GRC~ESC~1~0~Critical compliance breach — MD immediately, Board within 48 hours · POSH complaint — MD and Board
GRC~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
GRC~TSK~1~0~Quality assurance
GRC~SUB~1~1~Own the quality score reported to clients
GRC~SUB~1~2~Pre and post-dispatch audit programme
GRC~SUB~1~3~Defect root cause with Business Excellence
GRC~TSK~2~0~Compliance and legal
GRC~SUB~2~1~Client and regulatory compliance
GRC~SUB~2~2~Contract vetting and litigation
GRC~SUB~2~3~Audit observation closure
GRC~TSK~3~0~People
GRC~SUB~3~1~Manpower plan and vacancy closure
GRC~SUB~3~2~Appraisal cycle, knowledge tests and psychometric assessment
GRC~SUB~3~3~Payroll governance
GRC~SUB~3~4~POSH and disciplinary process
LEG~ACC~1~0~Contract drafting and vetting
LEG~ACC~2~0~Litigation and dispute management
LEG~ACC~3~0~Statutory and client compliance monitoring
LEG~MEA~1~0~Contract turnaround time
LEG~MEA~2~0~Pending case count
LEG~MEA~3~0~Zero penalties or adverse remarks
LEG~DEC~1~0~Vet and clear contracts within standard terms
LEG~ESC~1~0~Legal notice or regulatory action — MD and Board
LEG~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
LEG~TSK~1~0~Contracts
LEG~SUB~1~1~Draft and vet client, vendor, employment and partner agreements
LEG~SUB~1~2~Track renewal and expiry
LEG~TSK~2~0~Litigation
LEG~SUB~2~1~Respond to notices within timeline
LEG~SUB~2~2~Reduce exposure and cost
RISK~ACC~1~0~Enterprise risk register and quarterly review
RISK~ACC~2~0~Issue log and closure to agreed dates
RISK~ACC~3~0~Crisis management and business continuity plan
RISK~ACC~4~0~Insurance cover adequacy and claims
RISK~MEA~1~0~Risk register current and reviewed quarterly
RISK~MEA~2~0~Issues closed within agreed dates
RISK~MEA~3~0~Continuity plan tested annually
RISK~MEA~4~0~Insurance cover adequate to exposure
RISK~MEA~5~0~Zero uninsured material loss
RISK~DEC~1~0~Spend to Rs1,00,000 on appointment
RISK~DEC~2~0~Call a continuity test without notice
RISK~DEC~3~0~Log and escalate any issue
RISK~ESC~1~0~Any crisis, fraud or breach — MD and Board immediately
RISK~ESC~2~0~Risk rated high with no mitigation owner
RISK~ESC~3~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
RISK~TSK~1~0~Risk
RISK~SUB~1~1~Maintain the risk register with owner, likelihood and impact
RISK~SUB~1~2~Quarterly review with the Board
RISK~SUB~1~3~Track mitigation actions to closure
RISK~TSK~2~0~Issues
RISK~SUB~2~1~Log every issue raised by any function
RISK~SUB~2~2~Assign an owner and a date
RISK~SUB~2~3~Escalate anything unclosed past its date
RISK~TSK~3~0~Crisis and continuity
RISK~SUB~3~1~Business continuity plan per location
RISK~SUB~3~2~Crisis communication protocol
RISK~SUB~3~3~Data breach and fraud incident response with Technology
RISK~SUB~3~4~Annual continuity test
RISK~TSK~4~0~Insurance
RISK~SUB~4~1~Review cover against exposure annually
RISK~SUB~4~2~Manage claims
HRH~ACC~1~0~Manpower planning and vacancy closure
HRH~ACC~2~0~Payroll accuracy and statutory benefits
HRH~ACC~3~0~Appraisal cycle, clearance assessment and promotion decisions
HRH~ACC~4~0~Employee satisfaction and attrition
HRH~ACC~5~0~Compensation structure and grade mapping
HRH~ACC~6~0~Training, capability and the internship programme
HRH~MEA~1~0~Vacancy closure TAT
HRH~MEA~2~0~Payroll accuracy
HRH~MEA~3~0~Appraisal completion
HRH~MEA~4~0~Employee satisfaction score
HRH~MEA~5~0~Regrettable attrition
HRH~MEA~6~0~Zero statutory penalty
HRH~DEC~1~0~Spend to Rs3,00,000 on appointment
HRH~DEC~2~0~Approve hiring one level below any requesting manager with that manager''s superior
HRH~DEC~3~0~Issue people policy within the approved framework
HRH~ESC~1~0~POSH complaint — MD and Board where material
HRH~ESC~2~0~Statutory labour notice — MD
HRH~ESC~3~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
HRH~TSK~1~0~People operations
HRH~SUB~1~1~Annual manpower plan
HRH~SUB~1~2~Recruitment and onboarding
HRH~SUB~1~3~Payroll governance
HRH~SUB~1~4~Exit and settlement
HRH~TSK~2~0~Performance
HRH~SUB~2~1~Run the appraisal cycle on the Business Excellence framework
HRH~SUB~2~2~Administer knowledge and psychometric tests
HRH~SUB~2~3~Calibration and promotion decisions
HRH~TSK~3~0~Engagement
HRH~SUB~3~1~Employee satisfaction measurement
HRH~SUB~3~2~Attrition analysis and action
HRH~SUB~3~3~Rewards and recognition
HRH~TSK~4~0~Compliance
HRH~SUB~4~1~POSH, grievance and disciplinary process
HRH~SUB~4~2~Statutory registers and labour licences
LND~ACC~1~0~Induction and training delivery across the network
LND~ACC~2~0~Training effectiveness measured against defect and TAT data
LND~ACC~3~0~Internship programme — selection, deployment, evaluation and conversion
LND~ACC~4~0~Assessment content for the clearance levels
LND~MEA~1~0~Time to productivity for a new joiner
LND~MEA~2~0~Training coverage against calendar
LND~MEA~3~0~Defect reduction after training
LND~MEA~4~0~Intern project completion rate
LND~MEA~5~0~Intern to full-time conversion rate
LND~DEC~1~0~Spend to Rs75,000 on appointment
LND~DEC~2~0~Set the training calendar
LND~DEC~3~0~Require attendance at mandatory induction
LND~ESC~1~0~Any location operating without inducted staff
LND~ESC~2~0~Capability gap blocking a branch launch
LND~ESC~3~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
LND~TSK~1~0~Training
LND~SUB~1~1~Structured induction for every new joiner
LND~SUB~1~2~Branch Manager and Team Leader development
LND~SUB~1~3~Quality refresher training driven by defect themes
LND~SUB~1~4~Training calendar and attendance
LND~TSK~2~0~Internship programme
LND~SUB~2~1~Define project briefs with the sponsoring function
LND~SUB~2~2~Select and place interns
LND~SUB~2~3~Fortnightly review with the host chair
LND~SUB~2~4~Evaluate the deliverable and decide on conversion
LND~TSK~3~0~Assessment
LND~SUB~3~1~Maintain the knowledge-test bank per track
LND~SUB~3~2~Administer tests and record results
INT~ACC~1~0~Completion of the assigned project brief to the sponsor''s satisfaction
INT~MEA~1~0~Project delivered to brief
INT~MEA~2~0~Sponsor rating
INT~MEA~3~0~Conversion recommendation
INT~DEC~1~0~No financial authority
INT~ESC~1~0~Any client data concern — immediately to the host chair and Learning & Development
INT~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
INT~TSK~1~0~Project
INT~SUB~1~1~Agree the brief and deliverable with the sponsoring chair
INT~SUB~1~2~Work to the agreed milestones
INT~SUB~1~3~Present findings at the end of the placement
INT~TSK~2~0~Conduct
INT~SUB~2~1~Follow client confidentiality to employee standard
INT~SUB~2~2~Attend induction before any client-facing work
HRE~ACC~1~0~Employee records accuracy and audit readiness
HRE~ACC~2~0~Attendance and leave finalisation before payroll cut-off
HRE~ACC~3~0~Statutory documentation and registers
HRE~ACC~4~0~Exit processing
HRE~MEA~1~0~Files audit-ready
HRE~MEA~2~0~Attendance finalised before cut-off
HRE~MEA~3~0~Payroll input accuracy at or above 99%
HRE~MEA~4~0~Filings within due dates
HRE~DEC~1~0~No independent financial authority
HRE~ESC~1~0~Payroll discrepancy with financial impact · statutory filing at risk
HRE~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
HRE~TSK~1~0~Recruitment support
HRE~SUB~1~1~Coordinate approved manpower requirements
HRE~SUB~1~2~Interview scheduling
HRE~SUB~1~3~Pre-joining document verification
HRE~TSK~2~0~Records and payroll
HRE~SUB~2~1~Employee files and master data
HRE~SUB~2~2~Monthly attendance finalisation
HRE~SUB~2~3~Payroll input preparation
HRE~TSK~3~0~Statutory
HRE~SUB~3~1~PF, ESIC, Gratuity, Bonus and PT support
HRE~SUB~3~2~Statutory registers
HRE~SUB~3~3~Support labour audits
BEX~ACC~1~0~SOP authorship and version control
BEX~ACC~2~0~Process design for new services and clients
BEX~ACC~3~0~Branch and zone launch playbook
BEX~ACC~4~0~Job architecture, seat grades and the KRA/KPI framework
BEX~ACC~5~0~Change and transformation delivery
BEX~ACC~6~0~Go-ahead on every new process, system, tool and structural change before deployment
BEX~MEA~1~0~SOP coverage and currency
BEX~MEA~2~0~Launch time from approval to go-live
BEX~MEA~3~0~Milestones on time
BEX~MEA~4~0~KRA migration against deadline
BEX~DEC~1~0~Spend to Rs3,00,000 (proposed)
BEX~DEC~2~0~Approve or hold any new process, SOP, system or tool before it goes live
BEX~DEC~3~0~Mandate process change on control items, with MD arbitration
BEX~DEC~4~0~Publish and version SOPs
BEX~ESC~1~0~Operations refusal on a control mandate — MD · data integrity failure — MD
BEX~TSK~1~0~Process and SOP
BEX~SUB~1~1~Author and version-control every SOP
BEX~SUB~1~2~Design process for new services
BEX~SUB~1~3~Publish change to all functions
BEX~TSK~2~0~Project governance
BEX~SUB~2~1~PMO for cross-functional change
BEX~SUB~2~2~Launch playbook and stage gate
BEX~SUB~2~3~Review any tool before go-live
BEX~TSK~3~0~Org design
BEX~SUB~3~1~Job architecture and seat grades
BEX~SUB~3~2~KRA and KPI framework standard
BEX~SUB~3~3~Migrate all roles to one architecture
TEC~ACC~1~0~Technology roadmap and platform delivery
TEC~ACC~2~0~Information security and client data protection
TEC~ACC~3~0~System uptime and release quality
TEC~ACC~4~0~Technology budget and vendors
TEC~MEA~1~0~Roadmap completion
TEC~MEA~2~0~Uptime at or above 99.5%
TEC~MEA~3~0~On-time delivery rate
TEC~MEA~4~0~Defect leakage
TEC~MEA~5~0~Critical vulnerability count
TEC~DEC~1~0~Spend to Rs5,00,000 (proposed)
TEC~DEC~2~0~Set architecture and technology standards
TEC~DEC~3~0~Approve releases within the change process
TEC~ESC~1~0~Security incident or data breach — MD and Board immediately · outage affecting client delivery
TEC~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
TEC~TSK~1~0~Strategy and delivery
TEC~SUB~1~1~Roadmap aligned to business goals
TEC~SUB~1~2~Timely and quality releases
TEC~SUB~1~3~Architecture scalability
TEC~TSK~2~0~Security
TEC~SUB~2~1~Secure coding practices
TEC~SUB~2~2~Data security and regulatory compliance
TEC~SUB~2~3~Vulnerability assessment
TEC~SUB~2~4~Audit readiness
ENG~ACC~1~0~Release delivery and platform stability
ENG~ACC~2~0~Production support
ENG~MEA~1~0~Release cycle time
ENG~MEA~2~0~Defect leakage
ENG~MEA~3~0~Uptime
ENG~DEC~1~0~No independent financial authority
ENG~ESC~1~0~Production incident · security vulnerability
ENG~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
ENG~TSK~1~0~Build and run
ENG~SUB~1~1~Feature development against roadmap
ENG~SUB~1~2~Release and deployment
ENG~SUB~1~3~Production support and incident response
MIS~ACC~1~0~Management MIS accuracy and timeliness
MIS~ACC~2~0~Board and management dashboards
MIS~ACC~3~0~KPI definition, calculation and source registry
MIS~ACC~4~0~Reporting template standardisation
MIS~MEA~1~0~Report submission within TAT
MIS~MEA~2~0~Data accuracy at or above 99%
MIS~MEA~3~0~Zero major discrepancies in management reporting
MIS~MEA~4~0~KPI registry completeness
MIS~DEC~1~0~Spend to Rs1,00,000 (proposed)
MIS~DEC~2~0~Set reporting templates
MIS~DEC~3~0~Request data from any function on cadence
MIS~ESC~1~0~Any function failing to submit — MD · discrepancy between reported and actual — immediately
MIS~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
MIS~TSK~1~0~MIS
MIS~SUB~1~1~Consolidate Operations, Finance, Collections, Quality and HR data
MIS~SUB~1~2~Validate and reconcile before publication
MIS~SUB~1~3~Submit within defined TAT
MIS~TSK~2~0~Analytics
MIS~SUB~2~1~Branch, regional and client performance analysis
MIS~SUB~2~2~TAT, revenue and collection gap identification
MIS~SUB~2~3~Trend and variance analysis
MIS~TSK~3~0~Governance
MIS~SUB~3~1~Maintain the KPI registry — owner, calculation, source
MIS~SUB~3~2~Flag any function failing to submit on cadence
BD~ACC~1~0~New client empanelment pipeline
BD~ACC~2~0~Client onboarding coordination
BD~ACC~3~0~Pipeline accuracy and forecast
BD~MEA~1~0~New clients empanelled
BD~MEA~2~0~Conversion rate
BD~MEA~3~0~Pipeline accuracy vs actual
BD~MEA~4~0~Onboarding time to first case
BD~DEC~1~0~Spend to Rs75,000 (proposed)
BD~DEC~2~0~Client outreach within approved segment
BD~ESC~1~0~Any pricing or discount — MD only · non-standard terms — Legal then MD
BD~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
BD~TSK~1~0~Acquisition
BD~SUB~1~1~Identify and pursue new bank and NBFC mandates
BD~SUB~1~2~Empanelment documentation
BD~SUB~1~3~Onboarding coordination with Operations
BD~TSK~2~0~Pipeline
BD~SUB~2~1~Maintain the pipeline with realistic conversion
BD~SUB~2~2~Report without inflation
BID~ACC~1~0~Tender identification, qualification and submission
BID~ACC~2~0~Agreement preparation and execution within deadline
BID~ACC~3~0~EMD and bank guarantee tracking
BID~MEA~1~0~Agreement execution within deadline
BID~MEA~2~0~Zero disqualification from documentation gaps
BID~MEA~3~0~Technical qualification rate
BID~MEA~4~0~EMD and BG tracking accuracy
BID~DEC~1~0~Spend to Rs75,000 (proposed)
BID~DEC~2~0~Compile and submit bids within approved pricing
BID~ESC~1~0~Pricing in any bid — MD only · non-standard terms — Legal then MD · BG above limit — Finance Head
BID~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
BID~TSK~1~0~Bid pipeline
BID~SUB~1~1~Track GeM, bank portals, RFPs and RFQs
BID~SUB~1~2~Coordinate documentation, pricing input and credentials
BID~SUB~1~3~Ensure eligibility and specification compliance
BID~TSK~2~0~Contracts
BID~SUB~2~1~Prepare, compile and execute agreements
BID~SUB~2~2~Maintain the standard document repository
BID~TSK~3~0~Instruments
BID~SUB~3~1~EMD and BG tracking, renewal and refund
CS~ACC~1~0~Board and statutory secretarial compliance
CS~ACC~2~0~Statutory registers, filings and records
CS~MEA~1~0~Filings within due dates
CS~MEA~2~0~Zero adverse remarks or penalties
CS~MEA~3~0~Minutes circulated within timeline
CS~DEC~1~0~Spend to Rs50,000 (proposed)
CS~DEC~2~0~Sign statutory filings within delegation
CS~ESC~1~0~Any statutory non-compliance — MD and Board immediately
CS~ESC~2~0~Any new process, system, tool or structural change — Business Excellence sign-off before go-live
CS~TSK~1~0~Secretarial
CS~SUB~1~1~Meeting convening, notice and minutes
CS~SUB~1~2~Statutory registers and filings
CS~SUB~1~3~Compliance calendar$doc$, E'\n')) x;

insert into chair_accountability (chair_id, ord, statement)
select c.id, d.i, d.s from _dos d join chair c on c.code = d.code where d.kind='ACC';
insert into chair_measure (chair_id, ord, statement)
select c.id, d.i, d.s from _dos d join chair c on c.code = d.code where d.kind='MEA';
insert into chair_authority (chair_id, kind, ord, statement)
select c.id, 'DECIDE', d.i, d.s from _dos d join chair c on c.code = d.code where d.kind='DEC';
insert into chair_authority (chair_id, kind, ord, statement)
select c.id, 'ESCALATE', d.i, d.s from _dos d join chair c on c.code = d.code where d.kind='ESC';
insert into chair_task (chair_id, ord, task)
select c.id, d.i, d.s from _dos d join chair c on c.code = d.code where d.kind='TSK';
insert into chair_subtask (task_id, ord, statement)
select t.id, d.j, d.s from _dos d
  join chair c on c.code = d.code
  join chair_task t on t.chair_id = c.id and t.ord = d.i
where d.kind='SUB';
