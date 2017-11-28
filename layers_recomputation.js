gs.setProperty("glide.cmdb.logger.source.service_mapping", "info,warn,error,*");
gs.setProperty("glide.cmdb.logger.source.service_mapping.coordinator", "info,warn,error,*");
gs.setProperty("glide.cmdb.logger.source.service_mapping.template", "info,warn,error,*");
gs.setProperty("glide.cmdb.logger.source.service_mapping.matching", "info,warn,error,*");

var gr = new GlideRecord('cmdb_ci_service_discovered');
gr.get(<bs_sys_id>);
var layerId = gr.layer;
 
var layerGr = new GlideRecord('svc_layer');
layerGr.get(layerId);
 
var env = sn_svcmod.ServiceContainerFactory.loadEnvironment(layerGr.environment);
var allLayers = env.layers();
for (var i = 0 ; i < allLayers.length ; i++) {
                var layer = allLayers[i];
                layer.markRecomputationNeeded();
}
 
SNC.ServiceMappingFactory.recomputeLayer(layerGr);
