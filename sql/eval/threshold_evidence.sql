-- NOT run by the pipeline. Hand-labeled true pairs (product-level) and the recall-vs-volume table.
CREATE OR REPLACE TABLE pair_labels (sh_id STRING, ut_id STRING, is_dup BOOLEAN);
INSERT INTO pair_labels SELECT column1, column2, TRUE FROM VALUES
('SH-CANADA-CHIL-BLK-L','UT-1025'),('SH-HOKA-CB9-BLK-10','UT-1028'),
('SH-AD-GAZELLE-BLK-9','UT-1013'),('SH-AD-SAMBA-WHT-8','UT-1005'),
('SH-VANS-OLD-BLK-9','UT-1015'),('SH-AD-UB22-GRY-9','UT-1004'),
('SH-NK-DUNK-PND-9','UT-1012'),('SH-AD-STAN-WHT-9','UT-1029'),
('SH-REEBOK-CLUB-WHT-10','UT-1027'),('SH-NK-AF1-WHT-9','UT-1003'),
('SH-BIRK-ARIZ-BRN-42','UT-1019'),('SH-NK-TECH-BLK-L','UT-1017'),
('SH-RAY-AVIATOR-GLD','UT-1021'),
('SH-NK-AM90-WHT-10','UT-1001'),('SH-NK-AM90-WHT-11','UT-1002'),
('SH-NK-AM90-WHT-10','UT-1002'),('SH-NK-AM90-WHT-11','UT-1001'),
('SH-FJALL-KNKN-GRN','UT-1020'),('SH-TNF-NUPTSE-BLK-L','UT-1010'),
('SH-PMA-SUEDE-NVY-10','UT-1014'),('SH-DICKIES-874-BLK-32','UT-1030'),
('SH-LV-TRUCKER-BLU','UT-1008'),('SH-UGG-CLASSIC-CHE-7W','UT-1024'),
('SH-TIMB-6IN-WHT-10','UT-1023'),('SH-CONV-CT-WHT-10','UT-1016'),
('SH-CHAMPION-CREW-GRY-L','UT-1026'),('SH-DOC-1460-BLK-10','UT-1018'),
('SH-PTG-BTRSNP-GRY-L','UT-1011'),('SH-RLX-POLO-NVY-M','UT-1009'),
('SH-LV-501-IND-32','UT-1007'),('SH-NB-990V6-GRY-10','UT-1006'),
('SH-NK-JORDAN1-RED-10','UT-1022');

SELECT t.cut,
       COUNT_IF(l.is_dup AND c.sim >= t.cut) AS true_kept,
       COUNT_IF(l.is_dup) AS true_total,
       COUNT_IF(c.sim >= t.cut) AS pairs_sent_to_llm
FROM candidate_pairs c
LEFT JOIN pair_labels l ON l.sh_id = c.sh_id AND l.ut_id = c.ut_id,
     (SELECT column1 AS cut FROM VALUES (0.70),(0.75),(0.80),(0.85),(0.90)) t
GROUP BY t.cut ORDER BY t.cut;
