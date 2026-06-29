"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.isObjectNotEmpty = exports.executeAgentFlow = exports.resolveVariables = void 0;
const uuid_1 = require("uuid");
const lodash_1 = require("lodash");
const turndown_1 = __importDefault(require("turndown"));
const flowise_components_1 = require("flowise-components");
const Interface_1 = require("../Interface");
const _1 = require(".");
const Variable_1 = require("../database/entities/Variable");
const utils_1 = require("../utils");
const logger_1 = __importDefault(require("./logger"));
const utils_2 = require("../errors/utils");
const Execution_1 = require("../database/entities/Execution");
const addChatMesage_1 = require("./addChatMesage");
const ChatMessage_1 = require("../database/entities/ChatMessage");
const ControllerServiceUtils_1 = require("../enterprise/utils/ControllerServiceUtils");
const buildChatflow_1 = require("./buildChatflow");
const MAX_LOOP_COUNT = process.env.MAX_LOOP_COUNT ? parseInt(process.env.MAX_LOOP_COUNT) : 10;
/**
 * Add execution to database
 * @param {DataSource} appDataSource
 * @param {string} agentflowId
 * @param {IAgentflowExecutedData[]} agentFlowExecutedData
 * @param {string} sessionId
 * @returns {Promise<Execution>}
 */
const addExecution = async (appDataSource, agentflowId, agentFlowExecutedData, sessionId, workspaceId) => {
    const newExecution = new Execution_1.Execution();
    const bodyExecution = {
        agentflowId,
        state: 'INPROGRESS',
        sessionId,
        workspaceId,
        executionData: JSON.stringify(agentFlowExecutedData)
    };
    Object.assign(newExecution, bodyExecution);
    const execution = appDataSource.getRepository(Execution_1.Execution).create(newExecution);
    return await appDataSource.getRepository(Execution_1.Execution).save(execution);
};
/**
 * Update execution in database
 * @param {DataSource} appDataSource
 * @param {string} executionId
 * @param {Partial<IExecution>} data
 * @returns {Promise<void>}
 */
const updateExecution = async (appDataSource, executionId, workspaceId, data) => {
    const execution = await appDataSource.getRepository(Execution_1.Execution).findOneBy({
        id: executionId,
        workspaceId
    });
    if (!execution) {
        throw new Error(`Execution ${executionId} not found`);
    }
    const updateExecution = new Execution_1.Execution();
    const bodyExecution = {};
    if (data && data.executionData) {
        bodyExecution.executionData = typeof data.executionData === 'string' ? data.executionData : JSON.stringify(data.executionData);
    }
    if (data && data.state) {
        bodyExecution.state = data.state;
        if (data.state === 'STOPPED') {
            bodyExecution.stoppedDate = new Date();
        }
    }
    Object.assign(updateExecution, bodyExecution);
    appDataSource.getRepository(Execution_1.Execution).merge(execution, updateExecution);
    await appDataSource.getRepository(Execution_1.Execution).save(execution);
};
const resolveVariables = async (reactFlowNodeData, question, form, flowConfig, availableVariables, variableOverrides, uploadedFilesContent, chatHistory, componentNodes, agentFlowExecutedData, iterationContext, loopCounts) => {
    let flowNodeData = (0, lodash_1.cloneDeep)(reactFlowNodeData);
    const types = 'inputs';
    const resolveNodeReference = async (value) => {
        // If value is an array, process each element
        if (Array.isArray(value)) {
            return Promise.all(value.map((item) => resolveNodeReference(item)));
        }
        // If value is an object, process each property
        if (typeof value === 'object' && value !== null) {
            const resolvedObj = {};
            for (const [key, val] of Object.entries(value)) {
                resolvedObj[key] = await resolveNodeReference(val);
            }
            return resolvedObj;
        }
        // If value is not a string, return as is
        if (typeof value !== 'string')
            return value;
        // Convert legacy HTML content to markdown, preserving any markdown syntax within.
        // Legacy content from old getHTML() starts with a TipTap block tag (e.g. <p>text</p>).
        // Anchor with ^ to avoid matching intentional HTML/XML tags in user prompts
        // (e.g. <instruction><div>...</div></instruction>).
        if (/^\s*<(?:p|div|h[1-6]|ul|ol|blockquote|pre|table)\b/i.test(value)) {
            const turndownService = new turndown_1.default();
            // Disable escaping so markdown characters (e.g. ###, -, *) inside HTML are preserved as-is
            turndownService.escape = (str) => str;
            value = turndownService.turndown(value);
        }
        const matches = value.match(/{{(.*?)}}/g);
        if (!matches)
            return value;
        let resolvedValue = value;
        for (const match of matches) {
            // Remove {{ }} and trim whitespace
            const reference = match.replace(/[{}]/g, '').trim();
            const variableFullPath = reference;
            if (variableFullPath === _1.QUESTION_VAR_PREFIX) {
                resolvedValue = resolvedValue.replace(match, question);
                resolvedValue = uploadedFilesContent ? `${uploadedFilesContent}\n\n${resolvedValue}` : resolvedValue;
            }
            if (variableFullPath.startsWith('$form.')) {
                const variableValue = (0, lodash_1.get)(form, variableFullPath.replace('$form.', ''));
                if (variableValue != null) {
                    // For arrays and objects, stringify them to prevent toString() conversion issues
                    const formattedValue = Array.isArray(variableValue) || (typeof variableValue === 'object' && variableValue !== null)
                        ? JSON.stringify(variableValue)
                        : variableValue;
                    resolvedValue = resolvedValue.replace(match, formattedValue);
                }
            }
            if (variableFullPath === _1.FILE_ATTACHMENT_PREFIX) {
                resolvedValue = resolvedValue.replace(match, uploadedFilesContent);
            }
            if (variableFullPath === _1.CHAT_HISTORY_VAR_PREFIX) {
                resolvedValue = resolvedValue.replace(match, (0, flowise_components_1.convertChatHistoryToText)(chatHistory));
            }
            if (variableFullPath === _1.RUNTIME_MESSAGES_LENGTH_VAR_PREFIX) {
                resolvedValue = resolvedValue.replace(match, flowConfig?.runtimeChatHistoryLength ?? 0);
            }
            if (variableFullPath === _1.LOOP_COUNT_VAR_PREFIX) {
                // Get the current loop count from the most recent loopAgentflow node execution
                let currentLoopCount = 0;
                if (loopCounts && agentFlowExecutedData) {
                    // Find the most recent loopAgentflow node execution to get its loop count
                    const loopNodes = [...agentFlowExecutedData].reverse().filter((data) => data.data?.name === 'loopAgentflow');
                    if (loopNodes.length > 0) {
                        const latestLoopNode = loopNodes[0];
                        currentLoopCount = loopCounts.get(latestLoopNode.nodeId) || 0;
                    }
                }
                resolvedValue = resolvedValue.replace(match, currentLoopCount.toString());
            }
            if (variableFullPath === _1.CURRENT_DATE_TIME_VAR_PREFIX) {
                resolvedValue = resolvedValue.replace(match, new Date().toISOString());
            }
            if (variableFullPath.startsWith('$iteration')) {
                if (iterationContext && iterationContext.value) {
                    if (variableFullPath === '$iteration') {
                        // If it's exactly $iteration, stringify the entire value
                        const formattedValue = typeof iterationContext.value === 'object' ? JSON.stringify(iterationContext.value) : iterationContext.value;
                        resolvedValue = resolvedValue.replace(match, formattedValue);
                    }
                    else if (typeof iterationContext.value === 'string') {
                        resolvedValue = resolvedValue.replace(match, iterationContext?.value);
                    }
                    else if (typeof iterationContext.value === 'object') {
                        const iterationValue = (0, lodash_1.get)(iterationContext.value, variableFullPath.replace('$iteration.', ''));
                        // For arrays and objects, stringify them to prevent toString() conversion issues
                        const formattedValue = Array.isArray(iterationValue) || (typeof iterationValue === 'object' && iterationValue !== null)
                            ? JSON.stringify(iterationValue)
                            : iterationValue;
                        resolvedValue = resolvedValue.replace(match, formattedValue);
                    }
                }
            }
            if (variableFullPath.startsWith('$vars.')) {
                const vars = await (0, _1.getGlobalVariable)(flowConfig, availableVariables, variableOverrides);
                const variableValue = (0, lodash_1.get)(vars, variableFullPath.replace('$vars.', ''));
                if (variableValue != null) {
                    // For arrays and objects, stringify them to prevent toString() conversion issues
                    const formattedValue = Array.isArray(variableValue) || (typeof variableValue === 'object' && variableValue !== null)
                        ? JSON.stringify(variableValue)
                        : variableValue;
                    resolvedValue = resolvedValue.replace(match, formattedValue);
                }
            }
            if (variableFullPath.startsWith('$flow.') && flowConfig) {
                const variableValue = (0, lodash_1.get)(flowConfig, variableFullPath.replace('$flow.', ''));
                if (variableValue != null) {
                    // For arrays and objects, stringify them to prevent toString() conversion issues
                    const formattedValue = Array.isArray(variableValue) || (typeof variableValue === 'object' && variableValue !== null)
                        ? JSON.stringify(variableValue)
                        : variableValue;
                    resolvedValue = resolvedValue.replace(match, formattedValue);
                }
            }
            // Check if the variable is an output reference like `nodeId.output.path`
            const outputMatch = variableFullPath.match(/^(.*?)\.output\.(.+)$/);
            if (outputMatch && agentFlowExecutedData) {
                // Extract nodeId and outputPath from the match
                const [, nodeIdPart, outputPath] = outputMatch;
                // Clean nodeId (handle escaped underscores)
                const cleanNodeId = nodeIdPart.replace(/\\/g, '');
                // Find the last (most recent) matching node data instead of the first one
                const nodeData = [...agentFlowExecutedData].reverse().find((d) => d.nodeId === cleanNodeId);
                if (nodeData?.data?.output && outputPath.trim()) {
                    const variableValue = (0, lodash_1.get)(nodeData.data.output, outputPath);
                    if (variableValue !== undefined) {
                        // Replace the reference with actual value
                        const formattedValue = Array.isArray(variableValue) || (typeof variableValue === 'object' && variableValue !== null)
                            ? JSON.stringify(variableValue)
                            : variableValue;
                        // If the resolved value is exactly the match, replace it directly
                        if (resolvedValue === match) {
                            resolvedValue = formattedValue;
                        }
                        else {
                            // Otherwise do a standard string‐replace
                            resolvedValue = String(resolvedValue).replace(match, String(formattedValue));
                        }
                        // Skip fallback logic
                        continue;
                    }
                }
            }
            // Find node data in executed data
            // sometimes turndown value returns a backslash like `llmAgentflow\_1`, remove the backslash
            const cleanNodeId = variableFullPath.replace(/\\/g, '');
            // Find the last (most recent) matching node data instead of the first one
            const nodeData = agentFlowExecutedData
                ? [...agentFlowExecutedData].reverse().find((data) => data.nodeId === cleanNodeId)
                : undefined;
            if (nodeData && nodeData.data) {
                // Replace the reference with actual value
                const nodeOutput = nodeData.data['output'];
                const actualValue = nodeOutput?.content ?? nodeOutput?.http?.data;
                // For arrays and objects, stringify them to prevent toString() conversion issues
                const formattedValue = Array.isArray(actualValue) || (typeof actualValue === 'object' && actualValue !== null)
                    ? JSON.stringify(actualValue)
                    : actualValue?.toString() ?? match;
                resolvedValue = resolvedValue.replace(match, formattedValue);
            }
        }
        return resolvedValue;
    };
    const getParamValues = async (paramsObj) => {
        /*
         * EXAMPLE SCENARIO:
         *
         * 1. Agent node has inputParam: { name: "agentTools", type: "array", array: [{ name: "agentSelectedTool", loadConfig: true }] }
         * 2. Inputs contain: { agentTools: [{ agentSelectedTool: "requestsGet", agentSelectedToolConfig: { requestsGetHeaders: "Bearer {{ $vars.TOKEN }}" } }] }
         * 3. We need to resolve the variable in requestsGetHeaders because RequestsGet node defines requestsGetHeaders with acceptVariable: true
         *
         * STEP 1: Find all parameters with loadConfig=true (e.g., "agentSelectedTool")
         * STEP 2: Find their values in inputs (e.g., "requestsGet")
         * STEP 3: Look up component node definition for "requestsGet"
         * STEP 4: Find which of its parameters have acceptVariable=true (e.g., "requestsGetHeaders")
         * STEP 5: Find the config object (e.g., "agentSelectedToolConfig")
         * STEP 6: Resolve variables in config parameters that accept variables
         */
        // Helper function to find params with loadConfig recursively
        // Example: Finds ["agentModel", "agentSelectedTool"] from the inputParams structure
        const findParamsWithLoadConfig = (inputParams) => {
            const paramsWithLoadConfig = [];
            for (const param of inputParams) {
                // Direct loadConfig param (e.g., agentModel with loadConfig: true)
                if (param.loadConfig === true) {
                    paramsWithLoadConfig.push(param.name);
                }
                // Check nested array parameters (e.g., agentTools.array contains agentSelectedTool with loadConfig: true)
                if (param.type === 'array' && param.array && Array.isArray(param.array)) {
                    const nestedParams = findParamsWithLoadConfig(param.array);
                    paramsWithLoadConfig.push(...nestedParams);
                }
            }
            return paramsWithLoadConfig;
        };
        // Helper function to find value of a parameter recursively in nested objects/arrays
        // Example: Searches for "agentSelectedTool" value in complex nested inputs structure
        // Returns "requestsGet" when found in agentTools[0].agentSelectedTool
        const findParamValue = (obj, paramName) => {
            if (typeof obj !== 'object' || obj === null) {
                return undefined;
            }
            // Handle arrays (e.g., agentTools array)
            if (Array.isArray(obj)) {
                for (const item of obj) {
                    const result = findParamValue(item, paramName);
                    if (result !== undefined) {
                        return result;
                    }
                }
                return undefined;
            }
            // Direct property match
            if (Object.prototype.hasOwnProperty.call(obj, paramName)) {
                return obj[paramName];
            }
            // Recursively search nested objects
            for (const value of Object.values(obj)) {
                const result = findParamValue(value, paramName);
                if (result !== undefined) {
                    return result;
                }
            }
            return undefined;
        };
        // Helper function to process config parameters with acceptVariable
        // Example: Processes agentSelectedToolConfig object, resolving variables in requestsGetHeaders
        const processConfigParams = async (configObj, configParamWithAcceptVariables) => {
            if (typeof configObj !== 'object' || configObj === null) {
                return;
            }
            // Handle arrays of config objects
            if (Array.isArray(configObj)) {
                for (const item of configObj) {
                    await processConfigParams(item, configParamWithAcceptVariables);
                }
                return;
            }
            for (const [key, value] of Object.entries(configObj)) {
                // Only resolve variables for parameters that accept them
                // Example: requestsGetHeaders is in configParamWithAcceptVariables, so resolve "Bearer {{ $vars.TOKEN }}"
                if (configParamWithAcceptVariables.includes(key)) {
                    configObj[key] = await resolveNodeReference(value);
                }
            }
        };
        // STEP 1: Get all params with loadConfig from inputParams
        // Example result: ["agentModel", "agentSelectedTool"]
        const paramsWithLoadConfig = findParamsWithLoadConfig(reactFlowNodeData.inputParams);
        // STEP 2-6: Process each param with loadConfig
        for (const paramWithLoadConfig of paramsWithLoadConfig) {
            // STEP 2: Find the value of this parameter in the inputs
            // Example: paramWithLoadConfig="agentSelectedTool", paramValue="requestsGet"
            const paramValue = findParamValue(paramsObj, paramWithLoadConfig);
            if (paramValue && componentNodes[paramValue]) {
                // STEP 3: Get the node instance inputs to find params with acceptVariable
                // Example: componentNodes["requestsGet"] contains the RequestsGet node definition
                const nodeInstance = componentNodes[paramValue];
                const configParamWithAcceptVariables = [];
                // STEP 4: Find which parameters of the component accept variables
                // Example: RequestsGet has inputs like { name: "requestsGetHeaders", acceptVariable: true }
                if (nodeInstance.inputs && Array.isArray(nodeInstance.inputs)) {
                    for (const input of nodeInstance.inputs) {
                        if (input.acceptVariable === true) {
                            configParamWithAcceptVariables.push(input.name);
                        }
                    }
                }
                // Example result: configParamWithAcceptVariables = ["requestsGetHeaders", "requestsGetUrl", ...]
                // STEP 5: Look for the config object (paramName + "Config")
                // Example: Look for "agentSelectedToolConfig" in the inputs
                const configParamName = paramWithLoadConfig + 'Config';
                // Find all config values (handle arrays)
                const findAllConfigValues = (obj, paramName) => {
                    const results = [];
                    if (typeof obj !== 'object' || obj === null) {
                        return results;
                    }
                    // Handle arrays (e.g., agentTools array)
                    if (Array.isArray(obj)) {
                        for (const item of obj) {
                            results.push(...findAllConfigValues(item, paramName));
                        }
                        return results;
                    }
                    // Direct property match
                    if (Object.prototype.hasOwnProperty.call(obj, paramName)) {
                        results.push(obj[paramName]);
                    }
                    // Recursively search nested objects
                    for (const value of Object.values(obj)) {
                        results.push(...findAllConfigValues(value, paramName));
                    }
                    return results;
                };
                const configValues = findAllConfigValues(paramsObj, configParamName);
                // STEP 6: Process all config objects to resolve variables
                // Example: Resolve "Bearer {{ $vars.TOKEN }}" in requestsGetHeaders
                if (configValues.length > 0 && configParamWithAcceptVariables.length > 0) {
                    for (const configValue of configValues) {
                        await processConfigParams(configValue, configParamWithAcceptVariables);
                    }
                }
            }
        }
        // Original logic for direct acceptVariable params (maintains backward compatibility)
        // Example: Direct params like agentUserMessage with acceptVariable: true
        for (const key in paramsObj) {
            const paramValue = paramsObj[key];
            const isAcceptVariable = reactFlowNodeData.inputParams.find((param) => param.name === key)?.acceptVariable ?? false;
            if (isAcceptVariable) {
                paramsObj[key] = await resolveNodeReference(paramValue);
            }
        }
    };
    const paramsObj = flowNodeData[types] ?? {};
    await getParamValues(paramsObj);
    return flowNodeData;
};
exports.resolveVariables = resolveVariables;
/*
 * Gets all input connections for a specific node
 * @param {IEdge[]} edges - Array of all edges (connections) in the workflow
 * @param {string} nodeId - ID of the node to get input connections for
 * @returns {IEdge[]} Array of input connections for the specified node
 *
 * @example
 * // For llmAgentflow_2 which has two inputs from llmAgentflow_0 and llmAgentflow_1
 * const connections = getNodeInputConnections(nodes, edges, 'llmAgentflow_2');
 * // Returns array of two edge objects connecting to llmAgentflow_2
 */
function getNodeInputConnections(edges, nodeId) {
    // Filter edges where target matches the nodeId
    const inputConnections = edges.filter((edge) => edge.target === nodeId);
    // Sort connections by sourceHandle to maintain consistent order
    // This is important for nodes that have multiple inputs that need to be processed in order
    inputConnections.sort((a, b) => {
        // Extract index from sourceHandle (e.g., "output-0" vs "output-1")
        const indexA = parseInt(a.sourceHandle.split('-').find((part) => !isNaN(parseInt(part))) || '0');
        const indexB = parseInt(b.sourceHandle.split('-').find((part) => !isNaN(parseInt(part))) || '0');
        return indexA - indexB;
    });
    return inputConnections;
}
/**
 * Analyzes node dependencies and sets up expected inputs
 */
function setupNodeDependencies(nodeId, edges, nodes) {
    logger_1.default.debug(`\n🔍 Analyzing dependencies for node: ${nodeId}`);
    const inputConnections = getNodeInputConnections(edges, nodeId);
    const waitingNode = {
        nodeId,
        receivedInputs: new Map(),
        expectedInputs: new Set(),
        isConditional: false,
        conditionalGroups: new Map()
    };
    // Group inputs by their parent condition nodes
    const inputsByCondition = new Map();
    for (const connection of inputConnections) {
        const sourceNode = nodes.find((n) => n.id === connection.source);
        if (!sourceNode)
            continue;
        // Find if this input comes from a conditional branch
        const conditionParent = findConditionParent(connection.source, edges, nodes);
        if (conditionParent) {
            logger_1.default.debug(`  📌 Found conditional input from ${connection.source} (condition: ${conditionParent})`);
            waitingNode.isConditional = true;
            const group = inputsByCondition.get(conditionParent) || [];
            group.push(connection.source);
            inputsByCondition.set(conditionParent, group);
        }
        else {
            logger_1.default.debug(`  📌 Found required input from ${connection.source}`);
            waitingNode.expectedInputs.add(connection.source);
        }
    }
    // Set up conditional groups
    inputsByCondition.forEach((sources, conditionId) => {
        if (conditionId) {
            logger_1.default.debug(`  📋 Conditional group ${conditionId}: [${sources.join(', ')}]`);
            waitingNode.conditionalGroups.set(conditionId, sources);
        }
    });
    return waitingNode;
}
/**
 * Finds the parent condition node for a given node, if any
 */
function findConditionParent(nodeId, edges, nodes) {
    const currentNode = nodes.find((n) => n.id === nodeId);
    if (!currentNode)
        return null;
    if (currentNode.data.name === 'conditionAgentflow' ||
        currentNode.data.name === 'conditionAgentAgentflow' ||
        currentNode.data.name === 'humanInputAgentflow') {
        return currentNode.id;
    }
    let currentId = nodeId;
    const visited = new Set();
    let shouldContinue = true;
    while (shouldContinue) {
        if (visited.has(currentId)) {
            shouldContinue = false;
            continue;
        }
        visited.add(currentId);
        const parentEdge = edges.find((edge) => edge.target === currentId);
        if (!parentEdge) {
            shouldContinue = false;
            continue;
        }
        const parentNode = nodes.find((n) => n.id === parentEdge.source);
        if (!parentNode) {
            shouldContinue = false;
            continue;
        }
        if (parentNode.data.name === 'conditionAgentflow' ||
            parentNode.data.name === 'conditionAgentAgentflow' ||
            parentNode.data.name === 'humanInputAgentflow') {
            return parentNode.id;
        }
        currentId = parentNode.id;
    }
    return null;
}
/**
 * Checks if a node has received all required inputs
 */
function hasReceivedRequiredInputs(waitingNode) {
    logger_1.default.debug(`\n✨ Checking inputs for node: ${waitingNode.nodeId}`);
    // Check non-conditional required inputs
    for (const required of waitingNode.expectedInputs) {
        const hasInput = waitingNode.receivedInputs.has(required);
        logger_1.default.debug(`  📊 Required input ${required}: ${hasInput ? '✅' : '❌'}`);
        if (!hasInput)
            return false;
    }
    // Check conditional groups
    for (const [groupId, possibleSources] of waitingNode.conditionalGroups) {
        // Need at least one input from each conditional group
        const hasInputFromGroup = possibleSources.some((source) => waitingNode.receivedInputs.has(source));
        logger_1.default.debug(`  📊 Conditional group ${groupId}: ${hasInputFromGroup ? '✅' : '❌'}`);
        if (!hasInputFromGroup)
            return false;
    }
    return true;
}
/**
 * Determines which nodes should be ignored based on condition results
 * @param currentNode - The node being processed
 * @param result - The execution result from the node
 * @param edges - All edges in the workflow
 * @param nodeId - Current node ID
 * @returns Array of node IDs that should be ignored
 */
async function determineNodesToIgnore(currentNode, result, edges, nodeId) {
    const ignoreNodeIds = [];
    // Check if this is a decision node
    const isDecisionNode = currentNode.data.name === 'conditionAgentflow' ||
        currentNode.data.name === 'conditionAgentAgentflow' ||
        currentNode.data.name === 'humanInputAgentflow';
    if (isDecisionNode && result.output?.conditions) {
        const outputConditions = result.output.conditions;
        // safety net: if no conditions were fulfilled, don't ignore ALL children
        // treat the last condition as an else/default fallback
        const anyFulfilled = outputConditions.some((c) => c.isFulfilled === true);
        if (!anyFulfilled && outputConditions.length > 0) {
            // mark the last condition as fulfilled so at least one branch executes
            outputConditions[outputConditions.length - 1].isFulfilled = true;
        }
        // Find indexes of unfulfilled conditions
        const unfulfilledIndexes = outputConditions
            .map((condition, index) => condition.isFulfilled === false || !Object.prototype.hasOwnProperty.call(condition, 'isFulfilled') ? index : -1)
            .filter((index) => index !== -1);
        // Find nodes to ignore based on unfulfilled conditions
        for (const index of unfulfilledIndexes) {
            let ignoreEdge = edges.find((edge) => edge.source === nodeId && edge.sourceHandle === `${nodeId}-output-${index}`);
            // ponytail: humanInputAgentflow uses named handles (output-proceed/reject), not indexed
            if (!ignoreEdge && outputConditions[index] && outputConditions[index].type) {
                ignoreEdge = edges.find((edge) => edge.source === nodeId && edge.sourceHandle === `${nodeId}-output-${outputConditions[index].type}`);
            }
            if (ignoreEdge) {
                ignoreNodeIds.push(ignoreEdge.target);
            }
        }
    }
    return ignoreNodeIds;
}
/**
 * Process node outputs and handle branching logic
 */
async function processNodeOutputs({ nodeId, nodeName, result, humanInput, graph, nodes, edges, nodeExecutionQueue, waitingNodes, loopCounts, sseStreamer, chatId }) {
    logger_1.default.debug(`\n🔄 Processing outputs from node: ${nodeId}`);
    let updatedHumanInput = humanInput;
    const childNodeIds = graph[nodeId] || [];
    logger_1.default.debug(`  👉 Child nodes: [${childNodeIds.join(', ')}]`);
    const currentNode = nodes.find((n) => n.id === nodeId);
    if (!currentNode)
        return { humanInput: updatedHumanInput };
    // Get nodes to ignore based on conditions
    const ignoreNodeIds = await determineNodesToIgnore(currentNode, result, edges, nodeId);
    if (ignoreNodeIds.length) {
        logger_1.default.debug(`  ⏭️  Skipping nodes: [${ignoreNodeIds.join(', ')}]`);
    }
    for (const childId of childNodeIds) {
        if (ignoreNodeIds.includes(childId))
            continue;
        const childNode = nodes.find((n) => n.id === childId);
        if (!childNode)
            continue;
        logger_1.default.debug(`  📝 Processing child node: ${childId}`);
        let waitingNode = waitingNodes.get(childId);
        if (!waitingNode) {
            logger_1.default.debug(`    🆕 First time seeing node ${childId} - analyzing dependencies`);
            waitingNode = setupNodeDependencies(childId, edges, nodes);
            waitingNodes.set(childId, waitingNode);
        }
        waitingNode.receivedInputs.set(nodeId, result);
        logger_1.default.debug(`    ➕ Added input from ${nodeId}`);
        // Check if node is ready to execute
        if (hasReceivedRequiredInputs(waitingNode)) {
            logger_1.default.debug(`    ✅ Node ${childId} ready for execution!`);
            waitingNodes.delete(childId);
            nodeExecutionQueue.push({
                nodeId: childId,
                data: combineNodeInputs(waitingNode.receivedInputs),
                inputs: Object.fromEntries(waitingNode.receivedInputs)
            });
        }
        else {
            logger_1.default.debug(`    ⏳ Node ${childId} still waiting for inputs`);
            logger_1.default.debug(`      Has: [${Array.from(waitingNode.receivedInputs.keys()).join(', ')}]`);
            logger_1.default.debug(`      Needs: [${Array.from(waitingNode.expectedInputs).join(', ')}]`);
            if (waitingNode.conditionalGroups.size > 0) {
                logger_1.default.debug('      Conditional groups:');
                waitingNode.conditionalGroups.forEach((sources, groupId) => {
                    logger_1.default.debug(`        ${groupId}: [${sources.join(', ')}]`);
                });
            }
        }
    }
    if (nodeName === 'loopAgentflow' && result.output?.nodeID) {
        logger_1.default.debug(`  🔄 Looping back to node: ${result.output.nodeID}`);
        const loopCount = (loopCounts.get(nodeId) || 0) + 1;
        const maxLoop = result.output.maxLoopCount || MAX_LOOP_COUNT;
        if (loopCount < maxLoop) {
            logger_1.default.debug(`    Loop count: ${loopCount}/${maxLoop}`);
            loopCounts.set(nodeId, loopCount);
            nodeExecutionQueue.push({
                nodeId: result.output.nodeID,
                data: result.output,
                inputs: {}
            });
            // Clear humanInput when looping to prevent it from being reused
            if (updatedHumanInput) {
                logger_1.default.debug(`    🧹 Clearing humanInput for loop iteration`);
                updatedHumanInput = undefined;
            }
        }
        else {
            logger_1.default.debug(`    ⚠️ Maximum loop count (${maxLoop}) reached, stopping loop`);
            const fallbackMessage = result.output.fallbackMessage || `Loop completed after reaching maximum iteration count of ${maxLoop}.`;
            if (sseStreamer) {
                sseStreamer.streamTokenEvent(chatId, fallbackMessage);
            }
            result.output = { ...result.output, content: fallbackMessage };
        }
    }
    return { humanInput: updatedHumanInput };
}
/**
 * Combines inputs from multiple source nodes into a single input object
 * @param {Map<string, any>} receivedInputs - Map of inputs received from different nodes
 * @returns {any} Combined input data
 *
 * @example
 * const inputs = new Map();
 * inputs.set('node1', { json: { value: 1 }, text: 'Hello' });
 * inputs.set('node2', { json: { value: 2 }, text: 'World' });
 *
 * const combined = combineNodeInputs(inputs);
 *  Result:
 *  {
 *    json: {
 *      node1: { value: 1 },
 *      node2: { value: 2 }
 *    },
 *    text: 'Hello\nWorld'
 *  }
 */
function combineNodeInputs(receivedInputs) {
    // Filter out null/undefined inputs
    const validInputs = new Map(Array.from(receivedInputs.entries()).filter(([_, value]) => value !== null && value !== undefined));
    if (validInputs.size === 0) {
        return null;
    }
    if (validInputs.size === 1) {
        return Array.from(validInputs.values())[0];
    }
    // Initialize result object to store combined data
    const result = {
        json: {}
    };
    // Sort inputs by source node ID to ensure consistent ordering
    const sortedInputs = Array.from(validInputs.entries()).sort((a, b) => a[0].localeCompare(b[0]));
    for (const [sourceNodeId, inputData] of sortedInputs) {
        if (!inputData)
            continue;
        try {
            // Handle different types of input data
            if (typeof inputData === 'object') {
                // Merge JSON data
                if (inputData.json) {
                    result.json = {
                        ...result.json,
                        [sourceNodeId]: inputData.json
                    };
                }
                // Combine text data if present
                if (inputData.text) {
                    result.text = result.text ? `${result.text}\n${inputData.text}` : inputData.text;
                }
                // Merge binary data if present
                if (inputData.binary) {
                    result.binary = {
                        ...result.binary,
                        [sourceNodeId]: inputData.binary
                    };
                }
                // Handle error data
                if (inputData.error) {
                    result.error = inputData.error;
                }
            }
            else {
                // Handle primitive data types
                result.json[sourceNodeId] = inputData;
            }
        }
        catch (error) {
            // Log error but continue processing other inputs
            console.error(`Error combining input from node ${sourceNodeId}:`, error);
            result.error = error;
        }
    }
    // Special handling for text-only nodes
    if (Object.keys(result.json).length === 0 && result.text) {
        result.json = { text: result.text };
    }
    return result;
}
/**
 * Executes a single node in the workflow
 * @param params - Parameters needed for node execution
 * @returns The result of the node execution
 */
const executeNode = async ({ nodeId, reactFlowNode, nodes, edges, graph, reversedGraph, incomingInput, chatflow, chatId, sessionId, apiMessageId, evaluationRunId, parentExecutionId, pastChatHistory, prependedChatHistory, appDataSource, usageCacheManager, telemetry, componentNodes, cachePool, sseStreamer, baseURL, overrideConfig = {}, apiOverrideStatus = false, nodeOverrides = {}, variableOverrides = [], uploadedFilesContent = '', fileUploads, humanInput, agentFlowExecutedData = [], agentflowRuntime, abortController, parentTraceIds, analyticHandlers, isInternal, isRecursive, iterationContext, loopCounts, orgId, workspaceId, subscriptionId, productId }) => {
    try {
        if (abortController?.signal?.aborted) {
            throw new Error('Aborted');
        }
        // Stream progress event
        sseStreamer?.streamNextAgentFlowEvent(chatId, {
            nodeId,
            nodeLabel: reactFlowNode.data.label,
            status: 'INPROGRESS'
        });
        // Get node implementation
        const nodeInstanceFilePath = componentNodes[reactFlowNode.data.name].filePath;
        const nodeModule = await Promise.resolve(`${nodeInstanceFilePath}`).then(s => __importStar(require(s)));
        const newNodeInstance = new nodeModule.nodeClass();
        // Prepare node data
        let flowNodeData = (0, lodash_1.cloneDeep)(reactFlowNode.data);
        // Apply config overrides if needed
        if (overrideConfig && apiOverrideStatus) {
            flowNodeData = (0, utils_1.replaceInputsWithConfig)(flowNodeData, overrideConfig, nodeOverrides, variableOverrides);
        }
        // Get available variables and resolve them
        const availableVariables = await appDataSource.getRepository(Variable_1.Variable).findBy((0, ControllerServiceUtils_1.getWorkspaceSearchOptions)(workspaceId));
        // Prepare flow config
        let updatedState = (0, lodash_1.cloneDeep)(agentflowRuntime.state);
        const runtimeChatHistory = agentflowRuntime.chatHistory || [];
        const chatHistory = [...pastChatHistory, ...runtimeChatHistory];
        const flowConfig = {
            chatflowid: chatflow.id,
            chatflowId: chatflow.id,
            chatId,
            sessionId,
            apiMessageId,
            chatHistory,
            runtimeChatHistoryLength: Math.max(0, runtimeChatHistory.length - 1),
            state: updatedState,
            ...overrideConfig
        };
        if (iterationContext &&
            iterationContext.agentflowRuntime &&
            iterationContext.agentflowRuntime.state &&
            Object.keys(iterationContext.agentflowRuntime.state).length > 0) {
            updatedState = {
                ...iterationContext.agentflowRuntime.state,
                ...updatedState
            };
            flowConfig.state = updatedState;
            agentflowRuntime.state = updatedState;
        }
        // Resolve variables in node data
        let formValue = {};
        if ((0, exports.isObjectNotEmpty)(incomingInput.form)) {
            formValue = incomingInput.form;
        }
        else if ((0, exports.isObjectNotEmpty)(agentflowRuntime.form)) {
            formValue = agentflowRuntime.form;
        }
        const reactFlowNodeData = await (0, exports.resolveVariables)(flowNodeData, incomingInput.question ?? '', formValue, flowConfig, availableVariables, variableOverrides, uploadedFilesContent, chatHistory, componentNodes, agentFlowExecutedData, iterationContext, loopCounts);
        // Handle human input if present
        let humanInputAction;
        let updatedHumanInput = humanInput;
        if (agentFlowExecutedData.length) {
            const lastNodeOutput = agentFlowExecutedData[agentFlowExecutedData.length - 1]?.data?.output;
            humanInputAction = lastNodeOutput?.humanInputAction;
        }
        // This is when human in the loop is resumed
        if (humanInput && nodeId === humanInput.startNodeId) {
            reactFlowNodeData.inputs = { ...reactFlowNodeData.inputs, humanInput };
            // Remove the stopped humanInput from execution data
            agentFlowExecutedData = agentFlowExecutedData.filter((execData) => execData.nodeId !== nodeId);
            // Clear humanInput after it's been consumed to prevent subsequent humanInputAgentflow nodes from proceeding
            logger_1.default.debug(`🧹 Clearing humanInput after consumption by node: ${nodeId}`);
            updatedHumanInput = undefined;
        }
        // Check if this is the last node for streaming purpose
        const isLastNode = !isRecursive &&
            (!graph[nodeId] || graph[nodeId].length === 0 || (!humanInput && reactFlowNode.data.name === 'humanInputAgentflow'));
        if (incomingInput.question && incomingInput.form) {
            throw new Error('Question and form cannot be provided at the same time');
        }
        let finalInput;
        if (incomingInput.question) {
            // Prepare final question with uploaded content if any
            finalInput = uploadedFilesContent ? `${uploadedFilesContent}\n\n${incomingInput.question}` : incomingInput.question;
        }
        else if (incomingInput.form) {
            finalInput = Object.entries(incomingInput.form || {})
                .map(([key, value]) => `${key}: ${value}`)
                .join('\n');
        }
        // Prepare run parameters
        const runParams = {
            orgId,
            workspaceId,
            subscriptionId,
            chatId,
            sessionId,
            chatflowid: chatflow.id,
            chatflowId: chatflow.id,
            apiMessageId: flowConfig.apiMessageId,
            logger: logger_1.default,
            appDataSource,
            databaseEntities: _1.databaseEntities,
            usageCacheManager,
            componentNodes,
            cachePool,
            analytic: chatflow.analytic,
            uploads: fileUploads,
            baseURL,
            isLastNode,
            sseStreamer,
            pastChatHistory,
            prependedChatHistory,
            agentflowRuntime,
            abortController,
            analyticHandlers,
            parentTraceIds,
            humanInputAction,
            iterationContext,
            evaluationRunId
        };
        // Execute node
        let results = await newNodeInstance.run(reactFlowNodeData, finalInput, runParams);
        // Handle iteration node with recursive execution
        if (reactFlowNode.data.name === 'iterationAgentflow' &&
            results?.input?.iterationInput &&
            Array.isArray(results.input.iterationInput)) {
            logger_1.default.debug(`  🔄 Processing iteration node with ${results.input.iterationInput.length} items using recursive execution`);
            // Get child nodes for this iteration
            const childNodes = nodes.filter((node) => node.parentNode === nodeId);
            if (childNodes.length > 0) {
                logger_1.default.debug(`  📦 Found ${childNodes.length} child nodes for iteration`);
                // Create a new flow object containing only the nodes in this iteration block
                const iterationFlowData = {
                    nodes: childNodes,
                    edges: edges.filter((edge) => {
                        const sourceNode = nodes.find((n) => n.id === edge.source);
                        const targetNode = nodes.find((n) => n.id === edge.target);
                        return sourceNode?.parentNode === nodeId && targetNode?.parentNode === nodeId;
                    }),
                    viewport: { x: 0, y: 0, zoom: 1 }
                };
                // Create a modified chatflow for this iteration
                const iterationChatflow = {
                    ...chatflow,
                    flowData: JSON.stringify(iterationFlowData)
                };
                // Initialize array to collect results from iterations
                const iterationResults = [];
                // Execute sub-flow for each item in the iteration array
                for (let i = 0; i < results.input.iterationInput.length; i++) {
                    const item = results.input.iterationInput[i];
                    logger_1.default.debug(`  🔄 Processing iteration ${i + 1}/${results.input.iterationInput.length} recursively`);
                    // Create iteration context
                    const iterationContext = {
                        index: i,
                        value: item,
                        isFirst: i === 0,
                        isLast: i === results.input.iterationInput.length - 1,
                        sessionId: sessionId
                    };
                    try {
                        // Execute sub-flow recursively
                        const subFlowResult = await (0, exports.executeAgentFlow)({
                            componentNodes,
                            incomingInput,
                            chatflow: iterationChatflow,
                            chatId,
                            evaluationRunId,
                            appDataSource,
                            usageCacheManager,
                            telemetry,
                            cachePool,
                            sseStreamer,
                            baseURL,
                            isInternal,
                            uploadedFilesContent,
                            fileUploads,
                            signal: abortController,
                            isRecursive: true,
                            parentExecutionId,
                            iterationContext: {
                                ...iterationContext,
                                agentflowRuntime
                            },
                            orgId,
                            workspaceId,
                            subscriptionId,
                            productId
                        });
                        // Store the result
                        if (subFlowResult?.text) {
                            iterationResults.push(subFlowResult.text);
                        }
                        // Add executed data from sub-flow to main execution data with appropriate iteration context
                        if (subFlowResult?.agentFlowExecutedData) {
                            const subflowExecutedData = subFlowResult.agentFlowExecutedData.map((data) => ({
                                ...data,
                                data: {
                                    ...data.data,
                                    iterationIndex: i,
                                    iterationContext,
                                    parentNodeId: reactFlowNode.data.id
                                }
                            }));
                            // Add executed data to parent execution
                            agentFlowExecutedData.push(...subflowExecutedData);
                            // Update parent execution record with combined data if we have a parent execution ID
                            if (parentExecutionId) {
                                try {
                                    logger_1.default.debug(`  📝 Updating parent execution ${parentExecutionId} with iteration ${i + 1} data`);
                                    await updateExecution(appDataSource, parentExecutionId, workspaceId, {
                                        executionData: JSON.stringify(agentFlowExecutedData)
                                    });
                                }
                                catch (error) {
                                    console.error(`  ❌ Error updating parent execution: ${(0, utils_2.getErrorMessage)(error)}`);
                                }
                            }
                        }
                        // Merge the child iteration's runtime state back to parent
                        if (subFlowResult?.agentflowRuntime &&
                            subFlowResult.agentflowRuntime.state &&
                            Object.keys(subFlowResult.agentflowRuntime.state).length > 0) {
                            logger_1.default.debug(`  🔄 Merging iteration ${i + 1} runtime state back to parent`);
                            updatedState = {
                                ...updatedState,
                                ...subFlowResult.agentflowRuntime.state
                            };
                            // Update next iteration's runtime state
                            agentflowRuntime.state = updatedState;
                            // Update parent execution's runtime state
                            results.state = updatedState;
                        }
                    }
                    catch (error) {
                        console.error(`  ❌ Error in iteration ${i + 1}: ${(0, utils_2.getErrorMessage)(error)}`);
                        iterationResults.push(`Error in iteration ${i + 1}: ${(0, utils_2.getErrorMessage)(error)}`);
                    }
                }
                // Update the output with combined results
                results.output = {
                    ...(results.output || {}),
                    iterationResults,
                    content: iterationResults.join('\n')
                };
                logger_1.default.debug(`  📊 Completed all iterations. Total results: ${iterationResults.length}`);
            }
        }
        // Stop going through the current route if the node is a human task
        if (!humanInput && reactFlowNode.data.name === 'humanInputAgentflow') {
            const humanInputAction = {
                id: (0, uuid_1.v4)(),
                mapping: {
                    approve: 'Proceed',
                    reject: 'Reject'
                },
                elements: [
                    { type: 'agentflowv2-approve-button', label: 'Proceed' },
                    { type: 'agentflowv2-reject-button', label: 'Reject' }
                ],
                data: {
                    nodeId,
                    nodeLabel: reactFlowNode.data.label,
                    input: results.input
                }
            };
            const newWorkflowExecutedData = {
                nodeId,
                nodeLabel: reactFlowNode.data.label,
                data: {
                    ...results,
                    output: {
                        ...results.output,
                        humanInputAction
                    }
                },
                previousNodeIds: reversedGraph[nodeId] || [],
                status: 'STOPPED'
            };
            agentFlowExecutedData.push(newWorkflowExecutedData);
            sseStreamer?.streamNextAgentFlowEvent(chatId, {
                nodeId,
                nodeLabel: reactFlowNode.data.label,
                status: 'STOPPED'
            });
            sseStreamer?.streamAgentFlowExecutedDataEvent(chatId, agentFlowExecutedData);
            sseStreamer?.streamAgentFlowEvent(chatId, 'STOPPED');
            sseStreamer?.streamActionEvent(chatId, humanInputAction);
            return { result: results, shouldStop: true, agentFlowExecutedData, humanInput: updatedHumanInput };
        }
        // Stop going through the current route if the node is a agent node waiting for human input before using the tool
        if (reactFlowNode.data.name === 'agentAgentflow' && results?.output?.isWaitingForHumanInput) {
            const humanInputAction = {
                id: (0, uuid_1.v4)(),
                mapping: {
                    approve: 'Proceed',
                    reject: 'Reject'
                },
                elements: [
                    { type: 'agentflowv2-approve-button', label: 'Proceed' },
                    { type: 'agentflowv2-reject-button', label: 'Reject' }
                ],
                data: {
                    nodeId,
                    nodeLabel: reactFlowNode.data.label,
                    input: results.input
                }
            };
            const newWorkflowExecutedData = {
                nodeId,
                nodeLabel: reactFlowNode.data.label,
                data: {
                    ...results,
                    output: {
                        ...results.output,
                        humanInputAction
                    }
                },
                previousNodeIds: reversedGraph[nodeId] || [],
                status: 'STOPPED'
            };
            agentFlowExecutedData.push(newWorkflowExecutedData);
            sseStreamer?.streamNextAgentFlowEvent(chatId, {
                nodeId,
                nodeLabel: reactFlowNode.data.label,
                status: 'STOPPED'
            });
            sseStreamer?.streamAgentFlowExecutedDataEvent(chatId, agentFlowExecutedData);
            sseStreamer?.streamAgentFlowEvent(chatId, 'STOPPED');
            sseStreamer?.streamActionEvent(chatId, humanInputAction);
            return { result: results, shouldStop: true, agentFlowExecutedData, humanInput: updatedHumanInput };
        }
        return { result: results, agentFlowExecutedData, humanInput: updatedHumanInput };
    }
    catch (error) {
        logger_1.default.error(`[server]: Error executing node ${nodeId}: ${(0, utils_2.getErrorMessage)(error)}`);
        throw error;
    }
};
const checkForMultipleStartNodes = (startingNodeIds, isRecursive, nodes) => {
    // For non-recursive, loop through and check if each starting node is inside an iteration node, if yes, delete it
    const clonedStartingNodeIds = [...startingNodeIds];
    for (const nodeId of clonedStartingNodeIds) {
        const node = nodes.find((node) => node.id === nodeId);
        if (node?.extent === 'parent' && !isRecursive) {
            startingNodeIds.splice(startingNodeIds.indexOf(nodeId), 1);
        }
    }
    if (!isRecursive && startingNodeIds.length > 1) {
        throw new Error('Multiple starting nodes are not allowed');
    }
};
const parseFormStringToJson = (formString) => {
    const result = {};
    const lines = formString.split('\n');
    for (const line of lines) {
        const [key, value] = line.split(': ').map((part) => part.trim());
        if (key && value) {
            result[key] = value;
        }
    }
    return result;
};
/*
 * Function to traverse the flow graph and execute the nodes
 */
const executeAgentFlow = async ({ componentNodes, incomingInput, chatflow, chatId, evaluationRunId, appDataSource, telemetry, usageCacheManager, cachePool, sseStreamer, baseURL, isInternal, uploadedFilesContent, fileUploads, signal: abortController, isRecursive = false, parentExecutionId, iterationContext, isTool = false, orgId, workspaceId, subscriptionId, productId }) => {
    logger_1.default.debug('\n🚀 Starting flow execution');
    const question = incomingInput.question;
    const form = incomingInput.form;
    let overrideConfig = incomingInput.overrideConfig ?? {};
    const uploads = incomingInput.uploads;
    const userMessageDateTime = new Date();
    const chatflowid = chatflow.id;
    const sessionId = iterationContext?.sessionId || overrideConfig.sessionId || chatId;
    const humanInput = incomingInput.humanInput;
    // Validate history schema if provided
    if (incomingInput.history && incomingInput.history.length > 0) {
        if (!(0, _1.validateHistorySchema)(incomingInput.history)) {
            throw new Error('Invalid history format. Each history item must have: ' + '{ role: "apiMessage" | "userMessage", content: string }');
        }
    }
    const prependedChatHistory = incomingInput.history ?? [];
    const apiMessageId = (0, uuid_1.v4)();
    /*** Get chatflows and prepare data  ***/
    const flowData = chatflow.flowData;
    const parsedFlowData = JSON.parse(flowData);
    const nodes = (parsedFlowData.nodes || []).filter((node) => node.data.name !== 'stickyNoteAgentflow');
    const edges = parsedFlowData.edges;
    const { graph, nodeDependencies } = (0, utils_1.constructGraphs)(nodes, edges);
    const { graph: reversedGraph } = (0, utils_1.constructGraphs)(nodes, edges, { isReversed: true });
    const startInputType = nodes.find((node) => node.data.name === 'startAgentflow')?.data.inputs?.startInputType;
    if (!startInputType && !isRecursive) {
        throw new Error('Start input type not found');
    }
    // @ts-ignore
    if (isTool)
        sseStreamer = undefined; // If the request is from ChatflowTool, don't stream the response
    /*** Get API Config ***/
    const { nodeOverrides, variableOverrides, apiOverrideStatus } = (0, utils_1.getAPIOverrideConfig)(chatflow);
    /*
    graph {
        startAgentflow_0: [ 'conditionAgentflow_0' ],
        conditionAgentflow_0: [ 'llmAgentflow_0', 'llmAgentflow_1' ],
        llmAgentflow_0: [ 'llmAgentflow_2' ],
        llmAgentflow_1: [ 'llmAgentflow_2' ],
        llmAgentflow_2: []
      }
    */
    /*
      nodeDependencies {
        startAgentflow_0: 0,
        conditionAgentflow_0: 1,
        llmAgentflow_0: 1,
        llmAgentflow_1: 1,
        llmAgentflow_2: 2
      }
    */
    let status = 'INPROGRESS';
    let agentFlowExecutedData = [];
    let newExecution;
    const startingNodeIds = [];
    // Initialize execution queue
    const nodeExecutionQueue = [];
    const waitingNodes = new Map();
    const loopCounts = new Map();
    // Initialize runtime state for new execution
    let agentflowRuntime = {
        state: {},
        chatHistory: [],
        form: {}
    };
    let previousExecution;
    // If not a recursive call or parent execution not found, proceed normally
    if (!isRecursive) {
        const previousExecutions = await appDataSource.getRepository(Execution_1.Execution).find({
            where: {
                sessionId,
                agentflowId: chatflowid,
                workspaceId
            },
            order: {
                createdDate: 'DESC'
            }
        });
        if (previousExecutions.length) {
            previousExecution = previousExecutions[0];
        }
    }
    // If the state is persistent, get the state from the previous execution
    const startPersistState = nodes.find((node) => node.data.name === 'startAgentflow')?.data.inputs?.startPersistState;
    if (startPersistState === true && previousExecution) {
        const previousExecutionData = JSON.parse(previousExecution.executionData) ?? [];
        let previousState = {};
        if (Array.isArray(previousExecutionData) && previousExecutionData.length) {
            for (const execData of previousExecutionData.reverse()) {
                if (execData.data.state) {
                    previousState = execData.data.state;
                    break;
                }
            }
        }
        // Check if startState has been overridden from overrideConfig.startState and is enabled
        const startAgentflowNode = nodes.find((node) => node.data.name === 'startAgentflow');
        const isStartStateEnabled = nodeOverrides && startAgentflowNode
            ? nodeOverrides[startAgentflowNode.data.label]?.find((param) => param.name === 'startState')?.enabled ?? false
            : false;
        if (isStartStateEnabled && overrideConfig?.startState) {
            if (Array.isArray(overrideConfig.startState)) {
                // Handle array format: [{"key": "foo", "value": "foo4"}]
                const overrideStateObj = {};
                for (const item of overrideConfig.startState) {
                    if (item.key && item.value !== undefined) {
                        overrideStateObj[item.key] = item.value;
                    }
                }
                previousState = { ...previousState, ...overrideStateObj };
            }
            else if (typeof overrideConfig.startState === 'object') {
                // Object override: "startState": {...}
                previousState = { ...previousState, ...overrideConfig.startState };
            }
        }
        agentflowRuntime.state = previousState;
    }
    // If the start input type is form input, get the form values from the previous execution (form values are persisted in the same session)
    if (startInputType === 'formInput' && previousExecution) {
        const previousExecutionData = JSON.parse(previousExecution.executionData) ?? [];
        const previousStartAgent = previousExecutionData.find((execData) => execData.data.name === 'startAgentflow');
        if (previousStartAgent) {
            const previousStartAgentOutput = previousStartAgent.data.output;
            if (previousStartAgentOutput && typeof previousStartAgentOutput === 'object' && 'form' in previousStartAgentOutput) {
                const formValues = previousStartAgentOutput.form;
                if (typeof formValues === 'string') {
                    agentflowRuntime.form = parseFormStringToJson(formValues);
                }
                else {
                    agentflowRuntime.form = formValues;
                }
            }
        }
    }
    // If it is human input, find the last checkpoint and resume
    // Skip human input resumption for recursive iteration calls - they should start fresh
    if (humanInput && !(isRecursive && iterationContext)) {
        if (!previousExecution) {
            throw new Error(`No previous execution found for session ${sessionId}`);
        }
        let executionData = JSON.parse(previousExecution.executionData);
        let shouldUpdateExecution = false;
        // Handle different execution states
        if (previousExecution.state === 'STOPPED') {
            // Normal case - execution is stopped and ready to resume
            logger_1.default.debug(`  ✅ Previous execution is in STOPPED state, ready to resume`);
        }
        else if (previousExecution.state === 'ERROR') {
            // Check if second-to-last execution item is STOPPED and last is ERROR
            if (executionData.length >= 2) {
                const lastItem = executionData[executionData.length - 1];
                const secondLastItem = executionData[executionData.length - 2];
                if (lastItem.status === 'ERROR' && secondLastItem.status === 'STOPPED') {
                    logger_1.default.debug(`  🔄 Found ERROR after STOPPED - removing last error item to allow retry`);
                    logger_1.default.debug(`    Removing: ${lastItem.nodeId} (${lastItem.nodeLabel}) - ${lastItem.data?.error || 'Unknown error'}`);
                    // Remove the last ERROR item
                    executionData = executionData.slice(0, -1);
                    shouldUpdateExecution = true;
                }
                else {
                    throw new Error(`Cannot resume execution ${previousExecution.id} because it is in 'ERROR' state ` +
                        `and the previous item is not in 'STOPPED' state. Only executions that ended with a ` +
                        `STOPPED state (or ERROR after STOPPED) can be resumed.`);
                }
            }
            else {
                throw new Error(`Cannot resume execution ${previousExecution.id} because it is in 'ERROR' state ` +
                    `with insufficient execution data. Only executions in 'STOPPED' state can be resumed.`);
            }
        }
        else {
            // ponytail: retry loop for INPROGRESS->STOPPED race condition (SSE fires before DB commit)
            let retryExec = previousExecution;
            for (let i = 0; i < 10; i++) {
                await new Promise(r => setTimeout(r, 500));
                const freshList = await appDataSource.getRepository(Execution_1.Execution).find({ where: { id: retryExec.id } });
                if (freshList.length && freshList[0].state === 'STOPPED') { retryExec = freshList[0]; break; }
            }
            if (retryExec.state === 'STOPPED') {
                previousExecution = retryExec;
                executionData = JSON.parse(previousExecution.executionData);
            } else {
                throw new Error(`Cannot resume execution ${previousExecution.id} because it is in '${previousExecution.state}' state. Only executions in 'STOPPED' state (or 'ERROR' after 'STOPPED') can be resumed.`);
            }
        }
        let startNodeId = humanInput.startNodeId;
        // If startNodeId is not provided, find the last node with STOPPED status from execution data
        if (!startNodeId) {
            // Search in reverse order to find the last (most recent) STOPPED node
            const stoppedNode = [...executionData].reverse().find((data) => data.status === 'STOPPED');
            if (!stoppedNode) {
                throw new Error('No stopped node found in previous execution data to resume from');
            }
            startNodeId = stoppedNode.nodeId;
            logger_1.default.debug(`  🔍 Auto-detected stopped node to resume from: ${startNodeId} (${stoppedNode.nodeLabel})`);
        }
        // Verify that the node exists in previous execution
        const nodeExists = executionData.some((data) => data.nodeId === startNodeId);
        if (!nodeExists) {
            throw new Error(`Node ${startNodeId} not found in previous execution. ` +
                `This could indicate an invalid resume attempt or a modified flow.`);
        }
        startingNodeIds.push(startNodeId);
        checkForMultipleStartNodes(startingNodeIds, isRecursive, nodes);
        agentFlowExecutedData.push(...executionData);
        // Update execution data if we removed an error item
        if (shouldUpdateExecution) {
            logger_1.default.debug(`  📝 Updating execution data after removing error item`);
            await updateExecution(appDataSource, previousExecution.id, workspaceId, {
                executionData: JSON.stringify(executionData),
                state: 'INPROGRESS'
            });
        }
        // Get last state
        const lastState = executionData[executionData.length - 1].data.state;
        // Update agentflow runtime state
        agentflowRuntime.state = lastState ?? {};
        // Update execution state to INPROGRESS
        await updateExecution(appDataSource, previousExecution.id, workspaceId, {
            state: 'INPROGRESS'
        });
        newExecution = previousExecution;
        parentExecutionId = previousExecution.id;
        // Update humanInput with the resolved startNodeId
        humanInput.startNodeId = startNodeId;
    }
    else if (isRecursive && parentExecutionId) {
        const { startingNodeIds: startingNodeIdsFromFlow } = (0, _1.getStartingNode)(nodeDependencies);
        startingNodeIds.push(...startingNodeIdsFromFlow);
        checkForMultipleStartNodes(startingNodeIds, isRecursive, nodes);
        // For recursive calls with a valid parent execution ID, don't create a new execution
        // Instead, fetch the parent execution to use it
        const parentExecution = await appDataSource.getRepository(Execution_1.Execution).findOne({
            where: { id: parentExecutionId, workspaceId }
        });
        if (parentExecution) {
            logger_1.default.debug(`   📝 Using parent execution ID: ${parentExecutionId} for recursive call (iteration: ${!!iterationContext})`);
            newExecution = parentExecution;
        }
        else {
            console.warn(`   ⚠️ Parent execution ID ${parentExecutionId} not found, will create new execution`);
            newExecution = await addExecution(appDataSource, chatflowid, agentFlowExecutedData, sessionId, workspaceId);
            parentExecutionId = newExecution.id;
        }
    }
    else {
        const { startingNodeIds: startingNodeIdsFromFlow } = (0, _1.getStartingNode)(nodeDependencies);
        startingNodeIds.push(...startingNodeIdsFromFlow);
        checkForMultipleStartNodes(startingNodeIds, isRecursive, nodes);
        // Only create a new execution if this is not a recursive call
        newExecution = await addExecution(appDataSource, chatflowid, agentFlowExecutedData, sessionId, workspaceId);
        parentExecutionId = newExecution.id;
    }
    // Add starting nodes to queue
    startingNodeIds.forEach((nodeId) => {
        nodeExecutionQueue.push({
            nodeId,
            data: {},
            inputs: {}
        });
    });
    const maxIterations = process.env.MAX_ITERATIONS ? parseInt(process.env.MAX_ITERATIONS) : 1000;
    // Get chat history from ChatMessage table
    const pastChatHistory = (await appDataSource
        .getRepository(ChatMessage_1.ChatMessage)
        .find({
        where: {
            chatflowid,
            sessionId
        },
        order: {
            createdDate: 'ASC'
        }
    })
        .then((messages) => messages.map((message) => {
        const mappedMessage = {
            content: message.content,
            role: message.role === 'userMessage' ? 'user' : 'assistant'
        };
        const hasFileUploads = message.fileUploads && message.fileUploads !== '';
        const hasArtifacts = message.artifacts && message.artifacts !== '';
        const hasFileAnnotations = message.fileAnnotations && message.fileAnnotations !== '';
        const hasUsedTools = message.usedTools && message.usedTools !== '';
        if (hasFileUploads || hasArtifacts || hasFileAnnotations || hasUsedTools) {
            mappedMessage.additional_kwargs = {};
            if (hasFileUploads) {
                try {
                    mappedMessage.additional_kwargs.fileUploads = JSON.parse(message.fileUploads);
                }
                catch {
                    mappedMessage.additional_kwargs.fileUploads = message.fileUploads;
                }
            }
            if (hasArtifacts) {
                try {
                    mappedMessage.additional_kwargs.artifacts = JSON.parse(message.artifacts);
                }
                catch {
                    mappedMessage.additional_kwargs.artifacts = message.artifacts;
                }
            }
            if (hasFileAnnotations) {
                try {
                    mappedMessage.additional_kwargs.fileAnnotations = JSON.parse(message.fileAnnotations);
                }
                catch {
                    mappedMessage.additional_kwargs.fileAnnotations = message.fileAnnotations;
                }
            }
            if (hasUsedTools) {
                try {
                    mappedMessage.additional_kwargs.usedTools = JSON.parse(message.usedTools);
                }
                catch {
                    mappedMessage.additional_kwargs.usedTools = message.usedTools;
                }
            }
        }
        return mappedMessage;
    })));
    let iterations = 0;
    let currentHumanInput = humanInput;
    // For iteration calls, clear human input since they should start fresh
    if (isRecursive && iterationContext && humanInput) {
        currentHumanInput = undefined;
    }
    let analyticHandlers;
    let parentTraceIds;
    try {
        if (chatflow.analytic) {
            // Override config analytics
            let analyticInputs = {};
            if (overrideConfig?.analytics && Object.keys(overrideConfig.analytics).length > 0) {
                analyticInputs = {
                    ...overrideConfig.analytics
                };
            }
            analyticHandlers = flowise_components_1.AnalyticHandler.getInstance({ inputs: { analytics: analyticInputs } }, {
                orgId,
                workspaceId,
                appDataSource,
                databaseEntities: _1.databaseEntities,
                componentNodes,
                analytic: chatflow.analytic,
                chatId
            });
            await analyticHandlers.init();
            const flowName = chatflow.name || 'Agentflow';
            parentTraceIds = await analyticHandlers.onChainStart(flowName, form && Object.keys(form).length > 0 ? JSON.stringify(form) : question || '');
        }
    }
    catch (error) {
        logger_1.default.error(`[server]: Error initializing analytic handlers: ${(0, utils_2.getErrorMessage)(error)}`);
    }
    while (nodeExecutionQueue.length > 0 && status === 'INPROGRESS') {
        logger_1.default.debug(`\n▶️  Iteration ${iterations + 1}:`);
        logger_1.default.debug(`   Queue: [${nodeExecutionQueue.map((n) => n.nodeId).join(', ')}]`);
        if (iterations === 0 && !isRecursive) {
            sseStreamer?.streamAgentFlowEvent(chatId, 'INPROGRESS');
        }
        if (iterations++ > maxIterations) {
            throw new Error('Maximum iteration limit reached');
        }
        const currentNode = nodeExecutionQueue.shift();
        if (!currentNode)
            continue;
        const reactFlowNode = nodes.find((nd) => nd.id === currentNode.nodeId);
        if (!reactFlowNode || reactFlowNode === undefined || reactFlowNode.data.name === 'stickyNoteAgentflow')
            continue;
        let nodeResult;
        try {
            // Check for abort signal early in the loop
            if (abortController?.signal?.aborted) {
                throw new Error('Aborted');
            }
            logger_1.default.debug(`   🎯 Executing node: ${reactFlowNode?.data.label}`);
            // Execute current node
            const executionResult = await executeNode({
                nodeId: currentNode.nodeId,
                reactFlowNode,
                nodes,
                edges,
                graph,
                reversedGraph,
                incomingInput,
                chatflow,
                chatId,
                sessionId,
                apiMessageId,
                evaluationRunId,
                parentExecutionId,
                isInternal,
                pastChatHistory,
                prependedChatHistory,
                appDataSource,
                usageCacheManager,
                telemetry,
                componentNodes,
                cachePool,
                sseStreamer,
                baseURL,
                overrideConfig,
                apiOverrideStatus,
                nodeOverrides,
                variableOverrides,
                uploadedFilesContent,
                fileUploads,
                humanInput: currentHumanInput,
                agentFlowExecutedData,
                agentflowRuntime,
                abortController,
                parentTraceIds,
                analyticHandlers,
                isRecursive,
                iterationContext,
                loopCounts,
                orgId,
                workspaceId,
                subscriptionId,
                productId
            });
            if (executionResult.agentFlowExecutedData) {
                agentFlowExecutedData = executionResult.agentFlowExecutedData;
            }
            // Update humanInput if it was cleared by the executed node
            if (executionResult.humanInput !== currentHumanInput) {
                currentHumanInput = executionResult.humanInput;
            }
            if (executionResult.shouldStop) {
                status = 'STOPPED';
                break;
            }
            nodeResult = executionResult.result;
            // Add execution data
            agentFlowExecutedData.push({
                nodeId: currentNode.nodeId,
                nodeLabel: reactFlowNode.data.label,
                data: nodeResult,
                previousNodeIds: reversedGraph[currentNode.nodeId],
                status: 'FINISHED'
            });
            sseStreamer?.streamNextAgentFlowEvent(chatId, {
                nodeId: currentNode.nodeId,
                nodeLabel: reactFlowNode.data.label,
                status: 'FINISHED'
            });
            if (!isRecursive)
                sseStreamer?.streamAgentFlowExecutedDataEvent(chatId, agentFlowExecutedData);
            // Add to agentflow runtime state
            if (nodeResult && nodeResult.state) {
                agentflowRuntime.state = nodeResult.state;
            }
            if (nodeResult && nodeResult.chatHistory) {
                agentflowRuntime.chatHistory = [...(agentflowRuntime.chatHistory ?? []), ...nodeResult.chatHistory];
            }
            if (nodeResult && nodeResult.output && nodeResult.output.form) {
                agentflowRuntime.form = nodeResult.output.form;
            }
            if (nodeResult && nodeResult.output && nodeResult.output.ephemeralMemory) {
                pastChatHistory.length = 0;
            }
            // Process node outputs and handle branching
            const processResult = await processNodeOutputs({
                nodeId: currentNode.nodeId,
                nodeName: reactFlowNode.data.name,
                result: nodeResult,
                humanInput: currentHumanInput,
                graph,
                nodes,
                edges,
                nodeExecutionQueue,
                waitingNodes,
                loopCounts,
                sseStreamer,
                chatId
            });
            // Update humanInput if it was changed
            if (processResult.humanInput !== currentHumanInput) {
                currentHumanInput = processResult.humanInput;
            }
        }
        catch (error) {
            const isAborted = (0, utils_2.getErrorMessage)(error).includes('Aborted');
            const errorStatus = isAborted ? 'TERMINATED' : 'ERROR';
            const errorMessage = isAborted ? 'Flow execution was cancelled' : (0, utils_2.getErrorMessage)(error);
            status = errorStatus;
            // Add error info to execution data
            agentFlowExecutedData.push({
                nodeId: currentNode.nodeId,
                nodeLabel: reactFlowNode.data.label,
                previousNodeIds: reversedGraph[currentNode.nodeId] || [],
                data: {
                    id: currentNode.nodeId,
                    name: reactFlowNode.data.name,
                    error: errorMessage
                },
                status: errorStatus
            });
            // Stream events to client
            sseStreamer?.streamNextAgentFlowEvent(chatId, {
                nodeId: currentNode.nodeId,
                nodeLabel: reactFlowNode.data.label,
                status: errorStatus,
                error: isAborted ? undefined : errorMessage
            });
            // Only update execution record if this is not a recursive call
            if (!isRecursive) {
                sseStreamer?.streamAgentFlowExecutedDataEvent(chatId, agentFlowExecutedData);
                await updateExecution(appDataSource, newExecution.id, workspaceId, {
                    executionData: JSON.stringify(agentFlowExecutedData),
                    state: errorStatus
                });
                sseStreamer?.streamAgentFlowEvent(chatId, errorStatus);
            }
            if (parentTraceIds && analyticHandlers) {
                await analyticHandlers.onChainError(parentTraceIds, errorMessage, true);
            }
            throw new Error(errorMessage);
        }
        logger_1.default.debug(`/////////////////////////////////////////////////////////////////////////////`);
    }
    // check if there is any status stopped from agentFlowExecutedData
    const terminatedNode = agentFlowExecutedData.find((data) => data.status === 'TERMINATED');
    const errorNode = agentFlowExecutedData.find((data) => data.status === 'ERROR');
    const stoppedNode = agentFlowExecutedData.find((data) => data.status === 'STOPPED');
    if (terminatedNode) {
        status = 'TERMINATED';
    }
    else if (errorNode) {
        status = 'ERROR';
    }
    else if (stoppedNode) {
        status = 'STOPPED';
    }
    else {
        status = 'FINISHED';
    }
    // Only update execution record if this is not a recursive call
    if (!isRecursive) {
        await updateExecution(appDataSource, newExecution.id, workspaceId, {
            executionData: JSON.stringify(agentFlowExecutedData),
            state: status
        });
        sseStreamer?.streamAgentFlowEvent(chatId, status);
    }
    logger_1.default.debug(`\n🏁 Flow execution completed`);
    logger_1.default.debug(`   Status: ${status}`);
    // check if last agentFlowExecutedData.data.output contains the key "content"
    const lastNodeOutput = agentFlowExecutedData[agentFlowExecutedData.length - 1].data?.output;
    let content = lastNodeOutput?.content ?? ' ';
    /* Check for post-processing settings */
    let chatflowConfig = {};
    try {
        if (chatflow.chatbotConfig) {
            chatflowConfig = typeof chatflow.chatbotConfig === 'string' ? JSON.parse(chatflow.chatbotConfig) : chatflow.chatbotConfig;
        }
    }
    catch (e) {
        logger_1.default.error('[server]: Error parsing chatflow config:', e);
    }
    if (chatflowConfig?.postProcessing?.enabled === true && content) {
        try {
            const postProcessingFunction = JSON.parse(chatflowConfig?.postProcessing?.customFunction);
            const nodeInstanceFilePath = componentNodes['customFunctionAgentflow'].filePath;
            const nodeModule = await Promise.resolve(`${nodeInstanceFilePath}`).then(s => __importStar(require(s)));
            //set the outputs.output to EndingNode to prevent json escaping of content...
            const nodeData = {
                inputs: { customFunctionJavascriptFunction: postProcessingFunction }
            };
            const runtimeChatHistory = agentflowRuntime.chatHistory || [];
            const chatHistory = [...pastChatHistory, ...runtimeChatHistory];
            const options = {
                chatflowid: chatflow.id,
                sessionId,
                chatId,
                input: question || form,
                postProcessing: {
                    rawOutput: content,
                    chatHistory: (0, lodash_1.cloneDeep)(chatHistory),
                    sourceDocuments: lastNodeOutput?.sourceDocuments ? (0, lodash_1.cloneDeep)(lastNodeOutput.sourceDocuments) : undefined,
                    usedTools: lastNodeOutput?.usedTools ? (0, lodash_1.cloneDeep)(lastNodeOutput.usedTools) : undefined,
                    artifacts: lastNodeOutput?.artifacts ? (0, lodash_1.cloneDeep)(lastNodeOutput.artifacts) : undefined,
                    fileAnnotations: lastNodeOutput?.fileAnnotations ? (0, lodash_1.cloneDeep)(lastNodeOutput.fileAnnotations) : undefined
                },
                appDataSource,
                databaseEntities: _1.databaseEntities,
                workspaceId,
                orgId,
                logger: logger_1.default
            };
            const customFuncNodeInstance = new nodeModule.nodeClass();
            const customFunctionResponse = await customFuncNodeInstance.run(nodeData, question || form, options);
            const moderatedResponse = customFunctionResponse.output.content;
            if (typeof moderatedResponse === 'string') {
                content = moderatedResponse;
            }
            else if (typeof moderatedResponse === 'object') {
                content = '```json\n' + JSON.stringify(moderatedResponse, null, 2) + '\n```';
            }
            else {
                content = moderatedResponse;
            }
        }
        catch (e) {
            logger_1.default.error('[server]: Post Processing Error:', e);
        }
    }
    // remove credentialId from agentFlowExecutedData
    agentFlowExecutedData = agentFlowExecutedData.map((data) => (0, _1._removeCredentialId)(data));
    if (parentTraceIds && analyticHandlers) {
        await analyticHandlers.onChainEnd(parentTraceIds, content, true);
    }
    if (isRecursive) {
        return {
            agentFlowExecutedData,
            agentflowRuntime,
            status,
            text: content
        };
    }
    // Find the previous chat message with the same session/chat id and remove the action
    if (humanInput && Object.keys(humanInput).length) {
        let query = await appDataSource
            .getRepository(ChatMessage_1.ChatMessage)
            .createQueryBuilder('chat_message')
            .where('chat_message.chatId = :chatId', { chatId })
            .orWhere('chat_message.sessionId = :sessionId', { sessionId })
            .orderBy('chat_message.createdDate', 'DESC')
            .getMany();
        for (const result of query) {
            if (result.action) {
                try {
                    const newChatMessage = new ChatMessage_1.ChatMessage();
                    Object.assign(newChatMessage, result);
                    newChatMessage.action = null;
                    const cm = await appDataSource.getRepository(ChatMessage_1.ChatMessage).create(newChatMessage);
                    await appDataSource.getRepository(ChatMessage_1.ChatMessage).save(cm);
                    break;
                }
                catch (e) {
                    // error converting action to JSON
                }
            }
        }
    }
    let finalUserInput = incomingInput.question || ' ';
    if (startInputType === 'chatInput') {
        finalUserInput = question || humanInput?.feedback || ' ';
    }
    else if (startInputType === 'formInput') {
        if (form) {
            finalUserInput = Object.entries(form || {})
                .map(([key, value]) => `${key}: ${value}`)
                .join('\n');
        }
        else {
            finalUserInput = question || humanInput?.feedback || ' ';
        }
    }
    const userMessage = {
        role: 'userMessage',
        content: finalUserInput,
        chatflowid,
        chatType: evaluationRunId ? Interface_1.ChatType.EVALUATION : isInternal ? Interface_1.ChatType.INTERNAL : Interface_1.ChatType.EXTERNAL,
        chatId,
        sessionId,
        createdDate: userMessageDateTime,
        fileUploads: uploads ? JSON.stringify(fileUploads) : undefined,
        leadEmail: incomingInput.leadEmail,
        executionId: newExecution.id
    };
    await (0, addChatMesage_1.utilAddChatMessage)(userMessage, appDataSource);
    const apiMessage = {
        id: apiMessageId,
        role: 'apiMessage',
        content: content,
        chatflowid,
        chatType: evaluationRunId ? Interface_1.ChatType.EVALUATION : isInternal ? Interface_1.ChatType.INTERNAL : Interface_1.ChatType.EXTERNAL,
        chatId,
        sessionId,
        executionId: newExecution.id
    };
    if (lastNodeOutput?.sourceDocuments)
        apiMessage.sourceDocuments = JSON.stringify(lastNodeOutput.sourceDocuments);
    if (lastNodeOutput?.usedTools)
        apiMessage.usedTools = JSON.stringify(lastNodeOutput.usedTools);
    if (lastNodeOutput?.fileAnnotations)
        apiMessage.fileAnnotations = JSON.stringify(lastNodeOutput.fileAnnotations);
    if (lastNodeOutput?.artifacts)
        apiMessage.artifacts = JSON.stringify(lastNodeOutput.artifacts);
    if (lastNodeOutput?.reasonContent)
        apiMessage.reasonContent = JSON.stringify(lastNodeOutput.reasonContent);
    if (chatflow.followUpPrompts) {
        const followUpPromptsConfig = JSON.parse(chatflow.followUpPrompts);
        const followUpPrompts = await (0, flowise_components_1.generateFollowUpPrompts)(followUpPromptsConfig, apiMessage.content, {
            orgId,
            workspaceId,
            chatId,
            chatflowid,
            appDataSource,
            databaseEntities: _1.databaseEntities
        });
        if (followUpPrompts?.questions) {
            apiMessage.followUpPrompts = JSON.stringify(followUpPrompts.questions);
        }
    }
    if (lastNodeOutput?.humanInputAction && Object.keys(lastNodeOutput.humanInputAction).length)
        apiMessage.action = JSON.stringify(lastNodeOutput.humanInputAction);
    const chatMessage = await (0, addChatMesage_1.utilAddChatMessage)(apiMessage, appDataSource);
    logger_1.default.debug(`[server]: Finished running agentflow ${chatflowid}`);
    await telemetry.sendTelemetry('prediction_sent', {
        version: await (0, _1.getAppVersion)(),
        chatflowId: chatflowid,
        chatId,
        type: evaluationRunId ? Interface_1.ChatType.EVALUATION : isInternal ? Interface_1.ChatType.INTERNAL : Interface_1.ChatType.EXTERNAL,
        flowGraph: (0, _1.getTelemetryFlowObj)(nodes, edges),
        productId,
        subscriptionId
    }, orgId);
    /*** Prepare response ***/
    let result = {};
    result.text = content;
    result.question = incomingInput.question; // return the question in the response, this is used when input text is empty but question is in audio format
    result.form = form;
    result.chatId = chatId;
    result.chatMessageId = chatMessage?.id;
    result.followUpPrompts = JSON.stringify(apiMessage.followUpPrompts);
    result.executionId = newExecution.id;
    result.agentFlowExecutedData = agentFlowExecutedData;
    if (apiMessage.action)
        result.action = JSON.parse(apiMessage.action);
    if (sessionId)
        result.sessionId = sessionId;
    if ((0, buildChatflow_1.shouldAutoPlayTTS)(chatflow.textToSpeech) && result.text) {
        const options = {
            orgId,
            chatflowid,
            chatId,
            appDataSource,
            databaseEntities: _1.databaseEntities
        };
        if (sseStreamer) {
            await (0, buildChatflow_1.generateTTSForResponseStream)(result.text, chatflow.textToSpeech, options, chatId, chatMessage?.id, sseStreamer, abortController);
        }
    }
    return result;
};
exports.executeAgentFlow = executeAgentFlow;
/**
 * Utility function to check if an object is not empty, null, or undefined
 */
const isObjectNotEmpty = (obj) => {
    return obj && Object.keys(obj).length > 0 && obj.constructor === Object;
};
exports.isObjectNotEmpty = isObjectNotEmpty;
//# sourceMappingURL=buildAgentflow.js.map