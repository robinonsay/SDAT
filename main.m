config_name = input("Config File Name? ", "s");
if isempty(config_name)
    config_name = "default_config.json";
end
fid = fopen(config_name);
config_json = char(fread(fid, inf)');
fclose(fid);
config = jsondecode(config_json);
disp(config);