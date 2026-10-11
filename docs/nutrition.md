# 常用食物库来源

`foods.v1.json` 版本 `fuelform-foods-1.0.0`，八项条目。iOS与后端完全相同。数值是从 **USDA官方CSV**提取的每100g营养，非AI填充。

原始发布：USDA FoodData Central SR Legacy 2018-04；[官方数据下载页](https://fdc.nal.usda.gov/download-datasets/)。本次实际下载并读取 [官方CSV压缩包](https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip)。数据文件包含原始包SHA256，每个条目保留原始英文描述、FDC链接、来源版本。使用nutrient_id：1008（kcal）、1003（蛋白质）、1004（脂肪）、1005（碳水）。

条目含熟白米饭、生白米、香蕉、带皮苹果、去皮烤鸡胸肉、水煮鸡蛋、橄榄油、水煮西兰花。每项明确生/熟重、可食部分及烹饪方式。可查询原来源，但不是对所有中国菜的覆盖；复合菜、额外用油、不同品种和工艺需要人工修订或单独加项目。无匹配时明确AI估算，不伪造数据库来源。

复现：

```sh
curl --fail --location 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip' -o /tmp/usda-sr.zip
python3 scripts/build_food_catalog.py /tmp/usda-sr.zip
```

脚本按原始描述精确查条目，不根据相似名称猜值。库更新后必须变更版本并检查前后端一致；已保存餐次不从目录动态关联计算。
