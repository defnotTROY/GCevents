/**
 * Gordon College Departments Configuration
 * Only these departments are allowed for event categorization.
 */

export const DEPARTMENTS = [
    { id: 'CCS', name: 'College of Computer Studies', color: 'blue' },
    { id: 'CHTM', name: 'College of Hospitality and Tourism Management', color: 'red' },
    { id: 'CBA', name: 'College of Business and Accountancy', color: 'yellow' },
    { id: 'CEAS', name: 'College of Education, Arts, and Sciences', color: 'green' },
    { id: 'CAHS', name: 'College of Allied Health Studies', color: 'purple' },
    { id: 'General', name: 'General / University Wide', color: 'gray' } // Added General for non-exclusive events
];

export const DEPARTMENT_IDS = DEPARTMENTS.map(d => d.id);

export const getDepartmentName = (id) => {
    const dept = DEPARTMENTS.find(d => d.id === id);
    return dept ? dept.name : id;
};

export const getDepartmentColor = (id) => {
    const dept = DEPARTMENTS.find(d => d.id === id);
    return dept ? dept.color : 'gray';
};
