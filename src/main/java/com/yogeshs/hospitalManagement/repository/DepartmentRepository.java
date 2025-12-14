package com.yogeshs.hospitalManagement.repository;

import com.yogeshs.hospitalManagement.entity.Department;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DepartmentRepository extends JpaRepository<Department, Long> {
}