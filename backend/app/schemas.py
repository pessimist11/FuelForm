from datetime import date
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel

class Model(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra='forbid', allow_inf_nan=False)

class Nutrients(Model):
    kcal: float = Field(ge=0, le=10000)
    protein: float | None
    carbs: float | None
    fat: float | None

    @model_validator(mode='after')
    def macros(self):
        for value in (self.protein, self.carbs, self.fat):
            if value is not None and not 0 <= value <= 2000:
                raise ValueError('invalid macro')
        return self

class Candidate(Model):
    name: str = Field(min_length=1, max_length=200)
    food_id: str | None
    served_grams: float = Field(gt=0, le=10000)
    preparation: str = Field(min_length=1, max_length=200)
    estimated_nutrients: Nutrients  # Total served amount, never per100
    assumptions: list[str] = Field(max_length=12)
    questions: list[str] = Field(max_length=12)

class Recognition(Model):
    is_food: bool
    items: list[Candidate] = Field(max_length=30)
    message: str = Field(max_length=1000)

    @model_validator(mode='after')
    def contents(self):
        if self.is_food != bool(self.items):
            raise ValueError('isFood and items disagree')
        return self

class FoodSource(Model):
    kind: Literal['database', 'ai', 'demo']
    label: str
    version: str
    reference: str | None

class SuggestedFood(Model):
    name: str
    served_grams: float
    preparation: str
    basis: Literal['per100', 'total']
    nutrients: Nutrients
    source: FoodSource
    assumptions: list[str]
    questions: list[str]

class Analysis(Model):
    original_draft: Recognition
    mode: Literal['mock', 'openai', 'deepseek']
    is_food: bool
    items: list[SuggestedFood]
    message: str
    warnings: list[str]
    catalog_version: str

class PlanRequest(Model):
    start_date: date
    weeks: int = Field(ge=1, le=12)
    training_days: int = Field(ge=1, le=6)
    duration_minutes: int = Field(ge=15, le=120)
    equipment: list[Literal['bodyweight', 'dumbbell', 'barbell', 'machine']] = Field(min_length=1, max_length=4)
    experience: Literal['beginner', 'intermediate', 'advanced']
    goal: str = Field(min_length=1, max_length=300)
    avoid_exercise_ids: list[str] = Field(max_length=40)

class PlannedExercise(Model):
    exercise_id: str
    name: str
    sets: int = Field(ge=1, le=10)
    min_reps: int = Field(ge=1, le=100)
    max_reps: int = Field(ge=1, le=100)
    target_kg: float | None
    rest_seconds: int = Field(ge=15, le=600)

    @model_validator(mode='after')
    def ranges(self):
        if self.max_reps < self.min_reps or (self.target_kg is not None and not 0 <= self.target_kg <= 500):
            raise ValueError('invalid reps or weight')
        return self

class PlanDay(Model):
    day_key: date
    rest: bool
    exercises: list[PlannedExercise] = Field(max_length=12)

    @model_validator(mode='after')
    def rest_consistency(self):
        if self.rest == bool(self.exercises):
            raise ValueError('rest day must be empty; training day needs exercises')
        return self

class PlanDraft(Model):
    name: str = Field(min_length=1, max_length=200)
    days: list[PlanDay] = Field(min_length=1, max_length=84)
    notes: str = Field(max_length=2000)

class PlanResponse(Model):
    mode: Literal['mock', 'openai', 'deepseek']
    draft: PlanDraft
    warnings: list[str]
