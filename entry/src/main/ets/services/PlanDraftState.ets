import { PlanConstraints, WeeklyPlan } from '../models/PlanModels';

export class PlanDraftState {
  static planChanged(previous: WeeklyPlan | null, incoming: WeeklyPlan): boolean {
    return previous === null || previous.planId !== incoming.planId ||
      previous.planVersion !== incoming.planVersion || previous.constraintsJson !== incoming.constraintsJson;
  }

  static outsideWeek(days: string[], week: string[]): string[] {
    return days.filter((day: string) => week.indexOf(day) < 0);
  }

  /** Only editable form fields affect the draft indicator; selection order does not. */
  static key(c: PlanConstraints): string {
    const normalized: PlanConstraints = {
      startDay: '', targetKg: c.targetKg, gasScope: c.gasScope,
      budgetMinutes: c.budgetMinutes, budgetCost: c.budgetCost,
      availableDays: c.availableDays.slice().sort(), acceptedCategories: c.acceptedCategories.slice().sort(),
      usualTravelSubItem: c.usualTravelSubItem, usualTravelKm: c.usualTravelKm, excludedTemplateIds: []
    };
    return JSON.stringify(normalized);
  }
}
