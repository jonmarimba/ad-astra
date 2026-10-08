.data[]
| select(.id | startswith("ollamacloud/"))
| select(. as $model | ["-none", "-low", "-medium", "-high", "-xhigh", "-max"] | any(.[]; . as $suffix | $model.id | endswith($suffix)) | not)
| [.id, (.name // .id), "1"] | @tsv
