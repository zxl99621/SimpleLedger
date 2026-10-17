/// Drift 数据库 schema 版本号。
///
/// 改动表结构时必须同步 +1；备份恢复会拒绝高于此版本的备份文件。
const int kSimpleLedgerSchemaVersion = 33;
