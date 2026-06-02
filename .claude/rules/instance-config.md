# インスタンス設定

Output System Containerの接続情報。
他のrulesやagentファイルから参照される。

## Output System Container

| 設定 | 値 |
|------|-----|
| コンテナ名（フロントエンド） | hikaru20001117-gaido-test-output-system |
| コンテナ名（バックエンド） | hikaru20001117-gaido-test-output-system-backend |
| Dockerネットワーク名 | hikaru20001117-gaido-test-network |
| フロントエンドホストポート | 3001 |
| バックエンドホストポート | 3002 |
| コンテナ外からアクセスする時のフロントエンドURL | http://localhost:3001 |
| コンテナ外からアクセスする時のバックエンドURL | http://localhost:3002 |
| コンテナ内からアクセスする時のフロントエンドURL | http://hikaru20001117-gaido-test-output-system:3001 |
| コンテナ内からアクセスする時のバックエンドURL | http://hikaru20001117-gaido-test-output-system-backend:3002 |
