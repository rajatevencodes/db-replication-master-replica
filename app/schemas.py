from pydantic import BaseModel, ConfigDict


class ItemCreate(BaseModel):
    title: str
    description: str


class ItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str
