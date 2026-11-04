output "architecture" {
  description = "生产架构网络、计算、入口、数据和日志输出。"
  value = {
    network          = module.web.network, compute = module.web.compute
    entrypoint       = module.web.entrypoint, data = module.web.data
    storage_and_logs = module.web.storage_and_logs
  }
}
