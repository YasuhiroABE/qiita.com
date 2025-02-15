
.PHONY: help
help:
	@echo "See also: https://github.com/increments/qiita-cli"
	@echo "See also: https://qiita.com/Qiita/items/32c79014509987541130"
	@echo 
	@echo "🚀 コンテンツをブラウザでプレビューする"
	@echo " npx qiita preview"
	@echo "🚀 新しい記事を追加する"
	@echo " npx qiita new (記事のファイルのベース名)"
	@echo "🚀 記事を投稿、更新する"
	@echo " npx qiita publish (記事のファイルのベース名)"
	@echo "💁 コマンドのヘルプを確認する"
	@echo "  npx qiita help"

.PHONY: version
version:
	npx qiita version

.PHONY: update
update:
	npm install @qiita/qiita-cli@latest
