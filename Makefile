.PHONY: update cw-check help

update:  ## 更新 change-workflow 工具包
	./scripts/cw-update.sh

cw-check:  ## 检查工具包是否有新版本
	./scripts/cw-update.sh --check

help:  ## 显示可用命令
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
