# Run first script
system("ruby ZQUANT1_0_read_table_and_build_quantV2_subsets.rb")

sleep 2

# Run second script
system("ruby ZQUANT2_0_put_subsets_into_smashelito.rb")

sleep 2

# Run third script
system("ruby ZQUANT2_1_put_dispatches_into_smashelito.rb")
sleep 1
