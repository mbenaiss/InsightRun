import { WorkflowEntrypoint, type WorkflowEvent, type WorkflowStep } from 'cloudflare:workers'
import {
  type PlanJobBindings,
  type PlanJobParams,
  type PlanJobStep,
  runPlanJob,
} from '../routes/generateTrainingPlan'

export class TrainingPlanGenerationWorkflow extends WorkflowEntrypoint<
  PlanJobBindings,
  PlanJobParams
> {
  async run(event: Readonly<WorkflowEvent<PlanJobParams>>, step: WorkflowStep) {
    // Block and plan results are plain JSON, which is what WorkflowStep requires.
    return runPlanJob(this.env, event.payload, step as unknown as PlanJobStep, {
      instanceId: event.instanceId,
      createdAt: event.timestamp.getTime(),
    })
  }
}
