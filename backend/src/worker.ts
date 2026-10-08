// Workflow classes import `cloudflare:workers`, which only the Workers runtime provides:
// keeping them out of `index.ts` lets the test suite import the app directly.
export { default } from './index'
export { TrainingPlanGenerationWorkflow } from './workflows/trainingPlanGeneration'
