# SMOKE artifacts

Bằng chứng chạy TAY, bound vào `diff_sha256`. Một file cho mỗi ADP phase có mặt runtime.

Sinh + stamp bằng `.claude/tools/adp-smoke.sh`; `adp-checkpoint.sh` enforce.
Contract + lý do tồn tại: `../../CLAUDE.md` §5 "SMOKE gate".

**Quy tắc một dòng:** OBSERVED phải là output THẬT dán vào. Chữ "OK" không phân
biệt được với việc chưa chạy — và cả 5 lỗi khiến gate này ra đời đều lọt qua được
những thứ trông giống như đã kiểm.
