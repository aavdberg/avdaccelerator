targetScope = 'subscription'

// ========== //
// Parameters //
// ========== //
@description('Required. Location where to deploy AVD management plane.')
param avdManagementPlaneLocation string

@description('Optional. AVD workload subscription ID, multiple subscriptions scenario.')
param avdWorkloadSubsId string

@description('Required. Virtual machine time zone.')
param avdTimeZone string

@description('Required, The service providing domain services for Azure Virtual Desktop.')
param avdIdentityServiceProvider string

@description('AVD Resource Group Name for the service objects.')
param avdServiceObjectsRgName string

@description('Optional. AVD Application Group Name for the applications.')
param avdApplicationGroupNameRapp string

@description('AVD Application group for the session hosts. Desktop type.')
param avdApplicationGroupNameDesktop string

@description('Optional. AVD deploy remote app application group.')
param avdDeployRappGroup bool

@description('Optional. AVD deploy scaling plan.')
param avdDeployScalingPlan bool

@description('AVD Host Pool Name')
param avdHostPoolName string

@description('AVD scaling plan name')
param avdScalingPlanName string

@description('AVD scaling plan schedules')
param avdScalingPlanSchedules array

@description('AVD workspace name.')
param avdWorkSpaceName string

@description('Optional. AVD host pool Custom RDP properties.')
param avdHostPoolRdpProperties string

@allowed([
  'Personal'
  'Pooled'
])
@description('Optional. AVD host pool type. (Default: Pooled)')
param avdHostPoolType string

@allowed([
  'Automatic'
  'Direct'
])
@description('Optional. AVD host pool type. (Default: Automatic)')
param avdPersonalAssignType string

@allowed([
  'BreadthFirst'
  'DepthFirst'
])
@description('Required. AVD host pool load balacing type. (Default: BreadthFirst)')
param avdHostPoolLoadBalancerType string

@description('Optional. AVD host pool maximum number of user sessions per session host.')
param avhHostPoolMaxSessions int

@description('Optional. AVD host pool start VM on Connect.')
param avdStartVmOnConnect bool

@description('Required. Tags to be applied to resources')
param avdTags object

@description('Required. Tag to exclude resources from scaling plan. ')
param avdScalingPlanExclusionTag string

@description('Do not modify, used to set unique value for resource deployment.')
param time string = utcNow()

// =========== //
// Variable declaration //
// =========== //
var desktopApplicaitonGroups = [
  {
    name: avdApplicationGroupNameDesktop
    location: avdManagementPlaneLocation
    applicationGroupType: 'Desktop'
  }
]

var applicationApplicationGroups = [
  {
    name: avdApplicationGroupNameRapp
    location: avdManagementPlaneLocation
    applicationGroupType: 'RemoteApp'
  }
]
var avdHostPoolRdpPropertiesDomainServiceCheck = (avdIdentityServiceProvider == 'AAD') ? '${avdHostPoolRdpProperties}targetisaadjoined:i:1' : avdHostPoolRdpProperties
var finalApplicationGroups = avdDeployRappGroup ? concat(desktopApplicaitonGroups, applicationApplicationGroups) : desktopApplicaitonGroups

// =========== //
// Deployments //
// =========== //

// Hostpool.
module avdHostPool '../../../carml/1.2.0/Microsoft.DesktopVirtualization/hostpools/deploy.bicep' = {
  scope: resourceGroup('${avdWorkloadSubsId}', '${avdServiceObjectsRgName}')
  name: 'AVD-HostPool-${time}'
  params: {
    name: avdHostPoolName
    location: avdManagementPlaneLocation
    hostpoolType: avdHostPoolType
    startVMOnConnect: avdStartVmOnConnect
    customRdpProperty: avdHostPoolRdpPropertiesDomainServiceCheck
    loadBalancerType: avdHostPoolLoadBalancerType
    maxSessionLimit: avhHostPoolMaxSessions
    personalDesktopAssignmentType: avdPersonalAssignType
    tags: avdTags
  }
}

// Application groups.
module avdApplicationGroups '../../../carml/1.2.0/Microsoft.DesktopVirtualization/applicationgroups/deploy.bicep' = [for applicationGroup in finalApplicationGroups: {
  scope: resourceGroup('${avdWorkloadSubsId}', '${avdServiceObjectsRgName}')
  name: 'Deploy-AppGroup-${applicationGroup.name}-${time}'
  params: {
    name: applicationGroup.name
    location: applicationGroup.location
    applicationGroupType: applicationGroup.applicationGroupType
    hostpoolName: avdHostPool.outputs.name
    tags: avdTags
  }
  dependsOn: [
    avdHostPool
  ]
}]

// Workspace.
module avdWorkSpace '../../../carml/1.2.0/Microsoft.DesktopVirtualization/workspaces/deploy.bicep' = {
  scope: resourceGroup('${avdWorkloadSubsId}', '${avdServiceObjectsRgName}')
  name: 'Deploy-AVD-WorkSpace-${time}'
  params: {
      name: avdWorkSpaceName
      location: avdManagementPlaneLocation
      appGroupResourceIds: avdDeployRappGroup ? [
        '/subscriptions/${avdWorkloadSubsId}/resourceGroups/${avdServiceObjectsRgName}/providers/Microsoft.DesktopVirtualization/applicationgroups/${avdApplicationGroupNameDesktop}'
        '/subscriptions/${avdWorkloadSubsId}/resourceGroups/${avdServiceObjectsRgName}/providers/Microsoft.DesktopVirtualization/applicationgroups/${avdApplicationGroupNameRapp}'
      ]: [
        '/subscriptions/${avdWorkloadSubsId}/resourceGroups/${avdServiceObjectsRgName}/providers/Microsoft.DesktopVirtualization/applicationgroups/${avdApplicationGroupNameDesktop}'
      ]
      tags: avdTags
  }
  dependsOn: [
    avdHostPool
    avdApplicationGroups
  ]
}

// Scaling plan.
module avdScalingPlan '../../../carml/1.2.0/Microsoft.DesktopVirtualization/scalingplans/deploy.bicep' = if (avdDeployScalingPlan && (avdHostPoolType == 'Pooled'))  {
  scope: resourceGroup('${avdWorkloadSubsId}', '${avdServiceObjectsRgName}')
  name: 'Deploy-AVD-ScalingPlan-${time}'
  params: {
      name: avdScalingPlanName
      location: avdManagementPlaneLocation
      hostPoolType: 'Pooled' //avdHostPoolType
      exclusionTag: avdScalingPlanExclusionTag
      timeZone: avdTimeZone
      schedules: avdScalingPlanSchedules
      hostPoolReferences: [
        {
        hostPoolArmPath: '/subscriptions/${avdWorkloadSubsId}/resourceGroups/${avdServiceObjectsRgName}/providers/Microsoft.DesktopVirtualization/hostpools/${avdHostPoolName}'
        scalingPlanEnabled: true
        }
      ]
      tags: avdTags
  }
  dependsOn: [
    avdHostPool
    avdApplicationGroups
    avdWorkSpace
  ]
}

// =========== //
// Outputs //
// =========== //
output hostPooltoken string = avdHostPool.outputs.hostPoolRestrationInfo.token
