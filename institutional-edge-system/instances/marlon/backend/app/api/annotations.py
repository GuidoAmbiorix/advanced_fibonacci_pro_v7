from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime

from app.api import deps, database
from app.models.database import UserAnnotation, AnnotationTemplate, BotSlot
from app.schemas import schemas

router = APIRouter()

# ============================================================================
# USER ANNOTATIONS
# ============================================================================

@router.post("/slots/{slot_id}/annotations", response_model=schemas.AnnotationResponse)
def create_annotation(
    slot_id: int,
    annotation: schemas.AnnotationCreate,
    db: Session = Depends(database.get_db),
    # current_user = Depends(deps.get_current_active_user) # Uncomment when auth enabled
):
    """
    Create a new annotation (zone, line, etc.) for a specific slot.
    """
    # Verify slot exists
    slot = db.query(BotSlot).filter(BotSlot.id == slot_id).first()
    if not slot:
        raise HTTPException(status_code=404, detail="Bot Slot not found")

    db_obj = UserAnnotation(
        slot_id=slot_id,
        annotation_type=annotation.annotation_type,
        coordinates=annotation.coordinates,
        label=annotation.label,
        color=annotation.color,
        opacity=annotation.opacity,
        notes=annotation.notes,
        trade_action=annotation.trade_action,
        zone_type=annotation.zone_type
    )
    db.add(db_obj)
    db.commit()
    db.refresh(db_obj)
    return db_obj

@router.get("/slots/{slot_id}/annotations", response_model=List[schemas.AnnotationResponse])
def get_annotations(
    slot_id: int,
    db: Session = Depends(database.get_db),
    # current_user = Depends(deps.get_current_active_user)
):
    """
    Get all annotations for a specific slot.
    """
    annotations = db.query(UserAnnotation).filter(UserAnnotation.slot_id == slot_id).all()
    return annotations

@router.put("/annotations/{annotation_id}", response_model=schemas.AnnotationResponse)
def update_annotation(
    annotation_id: int,
    annotation_in: schemas.AnnotationUpdate,
    db: Session = Depends(database.get_db),
    # current_user = Depends(deps.get_current_active_user)
):
    """
    Update an existing annotation.
    """
    db_obj = db.query(UserAnnotation).filter(UserAnnotation.id == annotation_id).first()
    if not db_obj:
        raise HTTPException(status_code=404, detail="Annotation not found")

    update_data = annotation_in.dict(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_obj, field, value)

    db_obj.updated_at = datetime.utcnow() # Manually update timestamp if needed, though model has onupdate
    db.add(db_obj)
    db.commit()
    db.refresh(db_obj)
    return db_obj

@router.delete("/annotations/{annotation_id}", response_model=schemas.AnnotationResponse)
def delete_annotation(
    annotation_id: int,
    db: Session = Depends(database.get_db),
    # current_user = Depends(deps.get_current_active_user)
):
    """
    Delete an annotation.
    """
    db_obj = db.query(UserAnnotation).filter(UserAnnotation.id == annotation_id).first()
    if not db_obj:
        raise HTTPException(status_code=404, detail="Annotation not found")

    db.delete(db_obj)
    db.commit()
    return db_obj

# ============================================================================
# ANNOTATION TEMPLATES
# ============================================================================

@router.post("/templates", response_model=schemas.TemplateResponse)
def create_template(
    template: schemas.TemplateCreate,
    db: Session = Depends(database.get_db),
    # current_user = Depends(deps.get_current_active_user)
):
    """
    Save a set of annotations as a reusable template.
    """
    # user_id = current_user.id
    user_id = 1 # Default admin for now

    db_obj = AnnotationTemplate(
        user_id=user_id,
        template_name=template.template_name,
        description=template.description,
        annotations=template.annotations,
        is_public=template.is_public
    )
    db.add(db_obj)
    db.commit()
    db.refresh(db_obj)
    return db_obj

@router.get("/templates", response_model=List[schemas.TemplateResponse])
def get_templates(
    public_only: bool = False,
    db: Session = Depends(database.get_db),
    # current_user = Depends(deps.get_current_active_user)
):
    """
    Get user's templates and public templates.
    """
    user_id = 1 # Default
    
    query = db.query(AnnotationTemplate)
    if public_only:
        query = query.filter(AnnotationTemplate.is_public == True)
    else:
        # User's templates OR Public templates
        # Since logic might be complex with OR, let's just return all for now or filter by user
        query = query.filter((AnnotationTemplate.user_id == user_id) | (AnnotationTemplate.is_public == True))
        
    templates = query.all()
    return templates

@router.post("/slots/{slot_id}/templates/{template_id}/apply")
def apply_template(
    slot_id: int,
    template_id: int,
    db: Session = Depends(database.get_db),
    # current_user = Depends(deps.get_current_active_user)
):
    """
    Apply a template to a slot (copies annotations).
    """
    template = db.query(AnnotationTemplate).filter(AnnotationTemplate.id == template_id).first()
    if not template:
        raise HTTPException(status_code=404, detail="Template not found")
        
    slot = db.query(BotSlot).filter(BotSlot.id == slot_id).first()
    if not slot:
        raise HTTPException(status_code=404, detail="Bot Slot not found")

    # Create new annotations based on template
    new_annotations = []
    if template.annotations:
        for ann_data in template.annotations:
            # We assume ann_data matches schema structure
            new_ann = UserAnnotation(
                slot_id=slot_id,
                annotation_type=ann_data.get('annotation_type'),
                coordinates=ann_data.get('coordinates'),
                label=ann_data.get('label'),
                color=ann_data.get('color', '#3B82F6'),
                opacity=ann_data.get('opacity', 30),
                notes=ann_data.get('notes'),
                trade_action=ann_data.get('trade_action', 'NEUTRAL'),
                zone_type=ann_data.get('zone_type')
            )
            db.add(new_ann)
            new_annotations.append(new_ann)
    
    # Update use count
    template.use_count += 1
    db.commit()
    
    return {"message": "Template applied successfully", "annotations_created": len(new_annotations)}
