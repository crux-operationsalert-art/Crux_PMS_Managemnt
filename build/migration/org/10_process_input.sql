insert into process_input (process_id, what, from_chair_id)
select p.id, split_part(x,'~',2), c.id from unnest(string_to_array($doc$R1~Regional revenue roll-up~AVP
R1~Pipeline and conversion forecast~BD
R1~Tender award forecast~BID
R1~Billed revenue actuals~ACC
R10~Client feedback and lost-bid reasons~BID
R10~Rate benchmarks~ACC
R11~Service performance by client~MIS
R11~Quality score by client~GRC
R12P~Approved pricing band~MD
R12P~Local client list~BD
R13~Cost per case trend~FIN
R13~Contract escalation clause~LEG
R14~Cost per case by product~OPS
R14~Revenue by product~ACC
R15W~Territory plan~RM
R15W~Billing statement~ACC
R15W~Quality findings~GRC
R2~Branch revenue actuals~BM
R2~Client volume forecast~BD
R2~Billing data by branch~ACC
R2~Zone revenue actuals~BZ
R2~Billing data by zone~ACC
R6~Case volume by client~TL
R6~Client billing statement~ACC
R6~Local pipeline~BD
R8~Branch revenue actuals~BM
R8~Billing statement~ACC
R9~Partner-attributed billing~ACC
R9~Territory plan~BD
R9~Quality gate result~GRC
L1~Consolidated P&L~FIN
L1~Regional P&L pack~AVP
L1~Cost per case~OPS
L2~Branch P&L statements~BM
L2~Regional cost allocation~ACC
L2~Collection status~CCM
L2~Zone P&L statement~BZ
L6~Branch revenue statement~ACC
L6~Branch expense ledger~ACC
L6~Headcount cost~HRE
L6~Branch revenue and expense statement~ACC
L6~Collection status~CCM
X1~Cost per case model~OPS
X1~Function-wise spend~ACC
X1~Headcount cost~HRE
X1~Technology and cloud spend~TEC
X10~Cash flow forecast~FIN
X10~Facility utilisation~ACC
X11~Filing calendar~CS
X11~Liability computation~ACC
X2~Monthly expense ledger~ACC
X2~Approved branch budget~FIN
X3~Agency invoices and rates~ACC
X3~Case volume by product~MIS
X3~Field productivity~BM
X4~Approved admin budget~FIN
X4~Expense claims~ACC
X4~New location requirement~BEX
X5~Approved technology budget~FIN
X5~Vendor invoices~ACC
X6~Approved manpower plan~MD
X6~Attendance and leave data~HRE
X6~Payroll disbursement record~ACC
X7~Approved vendor invoices~ADM
X7~Empanelment and rate card~OPS
X7~Payment authorisation~FIN
X8~Requirement and specification~ADM
X8~Approved budget~FIN
X9~Asset register~ADM
X9~Exposure assessment~RISK
F1~Completed case data~TL
F1~Contract rate card~BID
F1~Client PO or work order~BD
F10P~Invoice and ageing data~ACC
F10P~Client contact list~BM
F11~Ageing beyond recovery policy~CCM
F11~Legal opinion~LEG
F2~Bank receipt advice~ACC
F2~Client remittance detail~CCE
F3~Ageing by client~CCM
F3~Client credit standing~BD
F3~Service impact assessment~OPS
F4~Collection target by region~FIN
F4~Ageing report by bucket~ACC
F4~Branch collection status~BM
F4~Dispute log~CCM
F4b~AR ledger and ageing~ACC
F4b~Collection actuals~CCM
F4b~Billing for the period~ACC
F5~Collection target by region~FIN
F5~Ageing by bucket and stage~ACC
F5~Dispute log~CCM
F5b~Certified accounts handed over~CE
F5b~Invoice and ageing data~ACC
F5b~Client payables contact~BD
F6~Collection forecast~CCM
F6~Payables schedule~ACC
F6~Capex and hiring plan~MD
F8~Bank statements~ACC
F8~Vendor and client documents~ADM
F9~Client deduction advice~ACC
F9~Case evidence~BM
D1~Daily TAT and pending report~MIS
D1~Client SLA schedule~BID
D1~Capacity position~AVP
D10~New location plan~BEX
D10~Asset register~ACC
D10~Approved admin budget~FIN
D11~SLA and quality standard~GRC
D11~Client SOP~BEX
D11~Case allocation~BM
D12W~Case inflow and priority~BM
D12W~Client SOP and format~BEX
D12W~Direction and standard~BEX
D13W~Daily case allocation~BM
D13W~Client SOP and checklist~BEX
D13W~Direction and standard~BEX
D14W~Field findings and evidence~FE
D14W~Report template~BEX
D14W~Direction and standard~BEX
D19~Client requirement variations~BD
D19~Delivery feasibility~OPS
D2~Regional performance pack~MIS
D2~Quality findings by region~GRC
D2~Succession bench view~GRC
D20~Client requirement~BD
D20~Capacity confirmation~OPS
D21~Client rejection log~GRC
D21~Root cause~GRC
D22~Volume by product~MIS
D22~Defect history~GRC
D23~Agent appointment records~OPS
D23~BGV clearance~GRC
D24~Case density by pin code~MIS
D24~Field headcount~HRE
D25~Standard and direction from the owning function~BEX
D26~Standard and direction from the owning function~BEX
D3~Daily allocation and TAT~TL
D3~Quality audit findings~GRC
D3~Client escalation log~BD
D4~Case inflow and priority~BM
D4~Client SOP and format~BEX
D5~Daily case allocation~BM
D5~Client SOP and checklist~BEX
D5~Route and territory plan~BM
D6~Field findings and evidence~FE
D6~Report template and client format~BEX
D6~Portal access~TEC
D7~Agency quality scorecard~GRC
D7~Rate benchmark~ACC
D7~Capacity gap by location~AVP
D8~Branch performance data~MIS
D8~Quality findings~GRC
D9~Case volume forecast by product~MIS
D9~Headcount availability~HRE
D9~Client volume commitment~BD
K1~Service performance by client~MIS
K1~Quality score by client~GRC
K1~Escalation history~OPS
K2~Escalation log~BM
K2~Root cause finding~GRC
K2~Client commitment~BD
K3~Costing and margin working~FIN
K3~Delivery feasibility~OPS
K3~Credit standing~CCM
K3~Contract terms~LEG
K4~Approved pricing band~MD
K4~Capacity confirmation~OPS
K4~Empanelment documents~BID
K5~Pricing approval~MD
K5~Credentials and financials~ACC
K5~Legal vetting~LEG
K5~Capacity confirmation~OPS
K6~Partner due diligence~GRC
K6~Draft agreement~LEG
K6~Territory and margin model~FIN
K7~Direction and standard~BEX
Q1~Dispatched report sample~BO
Q1~Client rejection log~BD
Q1~SOP standard~BEX
Q10~Client audit scope~BD
Q10~Process evidence~BEX
Q11~New joiner and agent list~HRE
Q11~Verification vendor output~GRC
Q12~Client retention obligations~BID
Q12~Regulatory position~LEG
Q13~Disclosures received~GRC
Q13~Investigation findings~RISK
Q14~Annual declarations~HRE
Q14~Vendor and partner register~ACC
Q15~Franchise file sample~PA
Q15~Brand and SOP standard~BEX
Q15~Client data access log~TEC
Q2~Published SOP set~BEX
Q2~Operating records~OPS
Q3~Client compliance schedule~BID
Q3~Statutory calendar~CS
Q3~Licence register~ADM
Q4~Draft commercial terms~BID
Q4~Credit and payment terms~FIN
Q5~Partner file sample~PA
Q5~Brand and data standard~BEX
Q5~Access log~TEC
Q6~Function risk submissions~GRC
Q6~Audit findings~GRC
Q6~Incident log~TEC
Q7~Issues raised by any function~GRC
Q7~Audit observations~GRC
Q8~Location and system dependency map~TEC
Q8~Client continuity obligations~BID
Q9~Empanelment renewal calendar~BID
Q9~Financials and credentials~ACC
Q9~Security posture~TEC
H1~Approved manpower plan~MD
H1~Role and grade definition~BEX
H1~Budget confirmation~FIN
H10~Skill gaps from the clearance assessment~BEX
H10~Defect themes~HRH
H10~New joiner list~HRE
H11~Project briefs from sponsoring chairs~BEX
H11~Placement capacity~OPS
H11~Stipend budget~FIN
H12~Direction and standard~BEX
H13~Chair definitions~BEX
H13~Market benchmarks~HRH
H14~Market salary data~HRH
H14~Budget envelope~FIN
H15~Performance data~MIS
H15~Budget~FIN
H16~Resignation and clearance~HRE
H16~Asset return~ADM
H16~Dues position~ACC
H17~Location list~OPS
H17~Headcount by location~HRE
H18~Standard and direction from the owning function~BEX
H2~Attendance and leave~HRE
H2~Salary structure~HRH
H2~Disbursement confirmation~ACC
H3~Level framework and test bank~BEX
H3~Performance data by chair~MIS
H3~Calibration input~OPS
H4~Exit interview data~HRE
H4~Engagement survey~HRE
H4~Succession bench view~AVP
H5~Skill gap from the matrix~BEX
H5~Defect themes~HRH
H5~New joiner list~HRE
H6~Joining and exit documentation~HRE
H6~Branch attendance~BM
H7~Volume forecast~MIS
H7~Approved budget~FIN
H7~Capacity gap~OPS
H8~Survey responses~HRE
H8~Attrition and exit data~HRE
H9~Direction and standard~BEX
E1~Client requirement and format~BD
E1~Defect root cause~GRC
E1~Operating reality~OPS
E10~Direction and standard~BEX
E11~Joiner, mover and leaver list~HRE
E11~Role-based access matrix~BEX
E12~Recovery objectives~RISK
E12~System inventory~TEC
E13~Contract terms~LEG
E13~Spend data~ACC
E14~Field workflow requirement~OPS
E14~Evidence standard~GRC
E15~Client technical specification~BID
E15~Volume and format requirement~OPS
E2~Operational data~OPS
E2~Financial data~FIN
E2~Quality data~GRC
E2~People data~HRE
E3~Expansion business case~RM
E3~Site and facilities plan~ADM
E3~Systems readiness~TEC
E4~Business requirement~BEX
E4~Operating pain points~OPS
E4~Approved budget~FIN
E4b~Prioritised backlog~TEC
E4b~Incident reports~OPS
E5~Client security requirement~BID
E5~Access register~HRE
E5~Regulatory position~LEG
E6~Org structure decisions~MD
E6~KPI source systems~MIS
E6~Appraisal outcomes~GRC
E7~Level framework and criteria~BEX
E7~Appraisal cycle dates~GRC
E7~Performance data~MIS
E8~Process or system change scope~BEX
E8~Affected chair list~GRC
E8~Training need~LND
E9~Manual effort baseline~BEX
E9~Volume data~MIS
G1~Annual plan and budget~MD
G1~Assurance findings~GRC
G1~Statutory position~CS
G10~Policy inventory~GRC
G10~Regulatory change~LEG
G11~Meeting schedule~MD
G11~Papers from each function~MIS
G12~Function performance packs~MIS
G12~Open action log~RISK
G2~Structure and grade proposal~BEX
G2~Capability assessment~GRC
G2~Cost impact~FIN
G3~Financial statements~FIN
G3~Board papers~MD
G3~Compliance confirmations~GRC
G4~Trial balance and schedules~ACC
G4~Operational volume data~MIS
G4~Audit observations~GRC
G5~Transaction data~ACE
G5~Statutory calendar~CS
G6~Definition decision~FIN
G7~Cash flow forecast~FIN
G7~Growth and capex plan~MD
G8~Surplus position~ACC
G8~Board mandate on risk appetite~BRD
G9~Proposed limits by chair~BEX
G9~Spend pattern~ACC
D15~Field escalations~FE
D15~Defect and rejection data~MIS
AC1~Transaction documents~ACE
AC1~Bank statements~ACC
AC2~Cut-off confirmations from every function~MIS
AC2~Accrual and provision inputs~FIN
AC3~Closed trial balance~ACC
AC3~Operational volume data~MIS
AC4~Bank statements~ACC
AC4~Receipt and payment records~ACE
AC5~Asset tagging and location data~ADM
AC5~Capitalisation approvals~FIN
AC6~Ageing beyond policy~CCM
AC6~Known disputes~CCM
AC7~Completed case data by period~MIS
AC7~Contract terms~BID
AC8~Branch expense claims~ADM
AC8~Branch revenue statements~MIS
AC9~Audit requirement list~GRC
AC9~Supporting schedules~ACC
LG1~Commercial terms~BID
LG1~Credit and payment terms~FIN
LG2~Executed agreements~BID
LG2~Renewal calendar~BD
LG3~Notice or claim received~GRC
LG3~Case facts and evidence~OPS
LG4~Location list~OPS
LG4~Licence calendar~ADM
LG5~Case documentation~HRE
LG5~Policy position~GRC
LG6~Partner agreement terms~BD
LG6~Brand usage audit findings~GRC
LG7~Client security requirement~BID
LG7~Data flow map~TEC
PC1~Case and billing statement for the period~ACC
PC1~Profit-sharing agreement terms~LEG
PC1~Collection status on sourced accounts~CCM
PC2~Partner-attributed billing~ACC
PC2~Collections received against those accounts~CCM
PC2~Agreement terms and share percentage~LEG
PC3~Submitted claim~PA
PC3~Computed entitlement~ACC
PC3~Regional confirmation of case data~RM
PC4~Reconciled claim~ACC
PC4~Variance explanation where any remains~ACC
PC4~Cash position~FIN
PC5~Territory and margin model~FIN
PC5~Draft agreement~LEG
PC5~Partner due diligence~GRC
PC6~Due diligence outcome~GRC
PC6~Territory plan~BD
PC6~Outstanding claim position~ACC$doc$, E'\n')) x
join process p on p.ref = split_part(x,'~',1)
join chair c on c.code = split_part(x,'~',3);
